--DECLARE @i BIGINT=0,@u BIGINT=0,@d BIGINT=0; EXEC [Gold].[usp_Load_Aggregate_Practice_Insights] @Mode='PROD',@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Practice_Insights
--  Author           :  AIH
--  Initial Date     :  21/10/2026
--  Notes:
--    Grain   : one row per (Tenant, Direction, Rank) -- six rows a tenant.
--    Pattern : full rebuild (DELETE + INSERT), pk from ROW_NUMBER().
--    Sources : Gold.Fact_Metric_Actuals, Config.Metric_Definitions,
--              Gold.Aggregate_Period_Targets, Gold.Dim_Date.
--
--    See the table DDL for why this ranks on MOVEMENT rather than distance from target, and
--    why the window is four weeks against four weeks rather than week against week.
--
--    ==> ONLY COMPLETE WEEKS. <== The current part-week would read as a collapse every time it
--    was looked at. @Last_Complete_Week is the Monday of the last week that has fully elapsed.
--
--    ==> A SMALL BASE IS NOT NEWS. <== A count going from 2 to 4 is +100% and means nothing, so
--    non-rate metrics need a prior-window base of at least @Min_Base before they can rank.
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [Gold].[usp_Load_Aggregate_Practice_Insights]
    @Mode           VARCHAR(10) = 'TEST',
    @Run_Inserts    BIGINT OUTPUT,
    @Run_Updates    BIGINT OUTPUT,
    @Run_Deletes    BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @My_Inserts BIGINT = 0, @My_Updates BIGINT = 0, @My_Deletes BIGINT = 0;
    DECLARE @Min_Base   DECIMAL(18,4) = 10.0;   -- per-window, before normalisation
    DECLARE @Block_Days INT = 28;

    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        -- ==> ASK Dim_Date WHERE THE WEEK STARTS; DO NOT RECOMPUTE IT. <== DATEPART(WEEKDAY)
        -- is relative to @@DATEFIRST, so deriving the Monday arithmetically agrees with the
        -- rest of the product only while that setting happens to be 7. A session under a
        -- different DATEFIRST would shift every window by up to six days and desynchronise
        -- these weeks from Week_Commencing_Date everywhere else, silently. The dimension
        -- already holds the answer.
        DECLARE @This_Week DATE = (SELECT Week_Commencing_Date FROM [Gold].[Dim_Date]
                                   WHERE Full_Date = CAST(SYSUTCDATETIME() AS DATE));
        DECLARE @Last_Complete_Week DATE = DATEADD(DAY, -7, @This_Week);

        DECLARE @Now_From DATE = DATEADD(DAY, -(@Block_Days - 7), @Last_Complete_Week);
        DECLARE @Now_To   DATE = DATEADD(DAY, 6, @Last_Complete_Week);
        DECLARE @Pre_From DATE = DATEADD(DAY, -@Block_Days, @Now_From);
        DECLARE @Pre_To   DATE = DATEADD(DAY, -1, @Now_From);
        -- ==> THERE ARE NO YEAR-AGO WINDOWS, DELIBERATELY. <== This panel reports RECENT
        -- MOVEMENT: four weeks against the four before. A window from a year ago is not
        -- recent movement, so it never answered the question being asked.
        --
        -- It was built to separate "this is new" from "this happens every autumn", and on
        -- the real data it could not do that either. Tenant 100, lapsed_deactivated by
        -- 28-day window: 31 -> 357 over the same two windows LAST year, = +1052%. Correct
        -- arithmetic off a base of 31, and still meaningless -- 357 deactivations in four
        -- weeks was a one-off tidy-up in Sept/Oct 2025. A year-on-year figure assumes last
        -- year's window was NORMAL and has no way to test that assumption, so one piece of
        -- housekeeping poisons the comparator permanently while still reading as a finding.
        --
        -- The owner's call, and the right one. Do not reintroduce it as a seasonality check:
        -- seasonality needs several prior years, and a single one cannot stand in for them.

        -- Working days per window per tenant: a count compared across a bank holiday is
        -- otherwise a fifth down on nothing.
        DROP TABLE IF EXISTS #wd;
        SELECT CAST(1 AS INT) AS Which,
               COUNT(*) AS Working_Days
        INTO   #wd
        FROM   [Gold].[Dim_Date]
        WHERE  Full_Date BETWEEN @Now_From AND @Now_To AND Is_Working_Day_England = 1
        UNION ALL
        SELECT 2, COUNT(*)
        FROM   [Gold].[Dim_Date]
        WHERE  Full_Date BETWEEN @Pre_From AND @Pre_To AND Is_Working_Day_England = 1;

        DROP TABLE IF EXISTS #daily;
        SELECT a.Tenant_ID,
               a.Metric,
               CASE WHEN d.Full_Date BETWEEN @Now_From AND @Now_To THEN 1
                    WHEN d.Full_Date BETWEEN @Pre_From AND @Pre_To THEN 2 END AS Which,
               d.Full_Date,
               SUM(CAST(a.Numerator   AS DECIMAL(38,6)))                     AS Numerator,
               SUM(CAST(a.Denominator AS DECIMAL(38,6)))                     AS Denominator
        INTO   #daily
        FROM   [Gold].[Fact_Metric_Actuals] a
        JOIN   [Gold].[Dim_Date] d ON d.pk_Date = a.fk_Date
        -- ==> EVERY METRIC IS NOW WRITTEN ONCE, SO EVERY METRIC IS SUMMED. <== Fact_Metric_Actuals
        -- holds one row per (site, practitioner) and the practice figure is a SUM over it. The
        -- old filter took the (-1,-1) 'practice total' slice, which no longer exists for anything;
        -- leaving it in place would have read nothing at all.
        --
        -- active_patients was the last exception and is no longer one: it has a single source
        -- again (the weekly snapshot, now carrying the dentist), so it sums like the rest.
        WHERE  d.Full_Date BETWEEN @Pre_From AND @Now_To
        -- ==> ONE ROW PER DATE, GUARANTEED. <== #snap picks the row matching the window's
        -- last date, so two rows sharing that date silently double everything downstream --
        -- which is what the rank guard caught the moment the year-ago join multiplied them
        -- out. Collapsing here makes the grain true rather than merely usually true.
        GROUP BY a.Tenant_ID, a.Metric,
                 CASE WHEN d.Full_Date BETWEEN @Now_From AND @Now_To THEN 1
                      WHEN d.Full_Date BETWEEN @Pre_From AND @Pre_To THEN 2 END,
                 d.Full_Date;

        DROP TABLE IF EXISTS #agg;
        SELECT Tenant_ID, Metric, Which,
               SUM(Numerator)   AS Numerator,
               SUM(Denominator) AS Denominator,
               MAX(Full_Date)   AS Last_Date
        INTO   #agg
        FROM   #daily
        GROUP BY Tenant_ID, Metric, Which;

        -- ==> A point_in_time METRIC IS A SNAPSHOT, AND IT IS WRITTEN WEEKLY, NOT DAILY. <==
        -- Sixteen of the active metrics are snapshots -- Active Patients, Outstanding
        -- Invoices, Deposit Ratio, Overdue Recalls among them -- and Fact_Metric_Actuals
        -- carries one row a week for them. Summing four of those and dividing by twenty
        -- working days is meaningless, and because the number of snapshots per window
        -- varies the result swings on nothing: Active Patients read +25% while the
        -- underlying count was quietly FALLING, 6,282 to 6,236. A snapshot compares at its
        -- latest reading in each window, which is what the practice would see on the day.
        DROP TABLE IF EXISTS #snap;
        SELECT dl.Tenant_ID, dl.Metric, dl.Which, dl.Numerator, dl.Denominator
        INTO   #snap
        FROM   #daily dl
        JOIN   #agg g ON g.Tenant_ID = dl.Tenant_ID AND g.Metric = dl.Metric
                     AND g.Which = dl.Which AND g.Last_Date = dl.Full_Date;

        -- ==> BRANCH ON Target_Type, NEVER ON Format_Type. <== Deposit Ratio is a percent
        -- AND a snapshot; treating every percent as a rate made it sum four weekly readings
        -- over four weekly denominators and swing wildly enough to top the list on noise.
        DROP TABLE IF EXISTS #val;
        SELECT g.Tenant_ID,
               g.Metric,
               g.Which,
               m.Range_Type,
               CASE WHEN m.Target_Type = 'cumulative' THEN CAST(1 AS BIT)
                    ELSE CAST(0 AS BIT) END                                  AS Per_Working_Day,
               CASE
                   WHEN m.Target_Type = 'rate'
                        THEN CASE WHEN g.Denominator <> 0
                                  THEN g.Numerator / g.Denominator END
                   WHEN m.Target_Type = 'cumulative'
                        THEN CASE WHEN w.Working_Days <> 0
                                  THEN g.Numerator / w.Working_Days END
                   ELSE CASE WHEN s.Denominator IS NOT NULL AND s.Denominator <> 0
                             THEN s.Numerator / s.Denominator
                             ELSE s.Numerator END
               END                                                           AS Val,
               CASE WHEN m.Target_Type = 'cumulative' THEN g.Numerator
                    ELSE s.Numerator END                                     AS Raw_Numerator,
               CAST(ISNULL(m.Area_Weight, 5) AS DECIMAL(9,2))                AS Area_Weight,
               CAST(m.Target_Type AS VARCHAR(16))                            AS Target_Type
        INTO   #val
        FROM   #agg g
        JOIN   [Config].[Metric_Definitions] m ON m.Metric_Key = g.Metric AND m.Is_Active = 1
        JOIN   #wd w ON w.Which = g.Which
        LEFT JOIN #snap s ON s.Tenant_ID = g.Tenant_ID AND s.Metric = g.Metric
                         AND s.Which = g.Which;

        -- Pair the windows and score the movement in the direction Range_Type calls good.
        DROP TABLE IF EXISTS #move;
        SELECT n.Tenant_ID,
               n.Metric,
               n.Per_Working_Day,
               n.Val                                                          AS Value_Now,
               p.Val                                                          AS Value_Before,
               (n.Val - p.Val) / ABS(p.Val)                                   AS Relative_Change,
               CASE WHEN n.Range_Type = 'below' THEN -((n.Val - p.Val) / ABS(p.Val))
                    ELSE (n.Val - p.Val) / ABS(p.Val) END                     AS Goodness,
               -- ==> IMPORTANCE BEATS MAGNITUDE, WHICH IS WHAT Area_Weight IS FOR. <==
               -- A slight fall in revenue matters more than a seismic swing in whether
               -- email addresses were captured, and the weights already say so:
               -- Total Revenue 45, Revenue per Clinical Hour 40, against Email Details 8
               -- and Deposit Ratio 5. Movement is capped at 100% so a metric with a small
               -- denominator cannot buy the top slot with a vast percentage -- on the live
               -- tenant that is Deposit Ratio at +137%, which now sits behind Average Plan
               -- Value at +40% because the latter is four times the weight.
               CASE WHEN ABS((n.Val - p.Val) / ABS(p.Val)) > 1.0 THEN 1.0
                    ELSE ABS((n.Val - p.Val) / ABS(p.Val)) END
                   * n.Area_Weight                                            AS Score
        INTO   #move
        FROM   #val n
        JOIN   #val p ON p.Tenant_ID = n.Tenant_ID AND p.Metric = n.Metric AND p.Which = 2
        WHERE  n.Which = 1
          AND  n.Val IS NOT NULL AND p.Val IS NOT NULL
          AND  ABS(p.Val) > 0.000001
          -- ==> A MOVE FROM A TRIVIAL BASE IS ARITHMETIC, NOT NEWS. <== A rate is exempt
          -- because it is already scale-free; everything with a countable base -- totals and
          -- snapshots alike -- has to clear @Min_Base before it may rank.
          AND  (n.Target_Type = 'rate' OR p.Raw_Numerator >= @Min_Base);

        DROP TABLE IF EXISTS #ranked;
        SELECT mv.Tenant_ID,
               CASE WHEN mv.Goodness < 0 THEN 'Watch' ELSE 'Good' END         AS Direction,
               ROW_NUMBER() OVER (
                   PARTITION BY mv.Tenant_ID, CASE WHEN mv.Goodness < 0 THEN 'Watch' ELSE 'Good' END
                   ORDER BY mv.Score DESC)                                    AS Rank_In_Direction,
               mv.Metric, mv.Per_Working_Day, mv.Value_Now, mv.Value_Before,
               mv.Relative_Change
        INTO   #ranked
        FROM   #move mv
        WHERE  ABS(mv.Goodness) >= 0.05;   -- below 5% movement nobody needs telling

        IF @Mode = 'PROD'
        BEGIN
            DELETE FROM [Gold].[Aggregate_Practice_Insights];
            SET @My_Deletes = @@ROWCOUNT;

            INSERT INTO [Gold].[Aggregate_Practice_Insights]
                (pk_Insight, Tenant_ID, Week_Commencing_Date, Direction, Rank_In_Direction,
                 Metric, Display_Name, Section, Format_Type, Per_Working_Day,
                 Value_Now, Value_Before, Relative_Change, Target_Value,
                 Narrative, DW_Created_At, DW_Updated_At)
            SELECT ROW_NUMBER() OVER (ORDER BY rk.Tenant_ID, rk.Direction, rk.Rank_In_Direction),
                   rk.Tenant_ID, @Last_Complete_Week, rk.Direction, rk.Rank_In_Direction,
                   rk.Metric, m.Display_Name, m.Section, m.Format_Type, rk.Per_Working_Day,
                   CAST(rk.Value_Now      AS DECIMAL(18,4)),
                   CAST(rk.Value_Before   AS DECIMAL(18,4)),
                   CAST(rk.Relative_Change AS DECIMAL(18,6)),
                   CAST(t.Target_Value    AS DECIMAL(18,4)),
                   NULL, SYSUTCDATETIME(), SYSUTCDATETIME()
            FROM   #ranked rk
            JOIN   [Config].[Metric_Definitions] m ON m.Metric_Key = rk.Metric
            LEFT JOIN [Gold].[Aggregate_Period_Targets] t
                   ON t.Tenant_ID = rk.Tenant_ID AND t.Metric = rk.Metric
                  AND t.Date_Grouping = 'Last 3 Months' AND t.Target_Level = 'Practice'
            WHERE  rk.Rank_In_Direction <= 3;
            SET @My_Inserts = @@ROWCOUNT;
        END

        DROP TABLE #wd; DROP TABLE #daily; DROP TABLE #agg; DROP TABLE #snap;
        DROP TABLE #val; DROP TABLE #move; DROP TABLE #ranked;
        --*********************************
        --**** Procedure logic ends    ****
        --*********************************
    END TRY

    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
