---------------------------------------------------------------------
--  Stored Procedure : Gold.usp_Load_Aggregate_Period_Targets
--  Author           : AIH
--  History          :
--    *01  ..  AIH  Precompute the target for each (Date_Grouping, Metric, Target_Level).
--    *02  29/10/2026  AIH  Node-aware, and built straight from Gold.Fact_Node_Targets.
--                          Fact_Daily_Targets is no longer in the chain.
--
--  THE TARGET FOR EVERY (NODE, LIVE PERIOD, METRIC, ROLE), PRECOMPUTED.
--
--  ==> THE DAILY EXPLOSION IS GONE, AND IT WAS NEVER NEEDED. <== This used to read
--  Gold.Fact_Daily_Targets: an annual target spread over every working day of its financial year,
--  264k rows on three tenants and about 1.3M once the hierarchy multiplied it, summed back up
--  here. But apportioning a target to a period is a RATIO, not an explosion --
--
--      cumulative      period target = SUM over each FY the period touches of
--                                        annual[FY] x (working days of the period in that FY
--                                                      / working days in that FY)
--      rate | stock    period target = the strictest annual across those years
--                                      (a threshold does not accumulate)
--
--  The sum matters: a rolling window reaches across the client's year end, and the two years can
--  carry different targets -- or target the metric in only one of them.
--
--  -- so it is one multiplication against a COUNT of dates. The daily table was a million rows
--  computed nightly to answer a question arithmetic answers directly, and nothing else read it:
--  zero measures in the model, one unused relationship.
--
--  ==> ONLY THE PERIODS THAT REACH TODAY ARE BUILT. <== Dim_Date_Grouping still carries FY21
--  onwards, but the app offers only the groupings whose dates run up to the latest date -- the
--  owner removed the historical ones because too many metrics lose their meaning when the current
--  month is missing. The same test is applied HERE, derived rather than listed, so the two cannot
--  drift: a grouping the app stops offering stops being built, and one it starts offering starts.
--  In practice that is Last 3 Months, Last 12 Months and the client's current financial year --
--  which year that is depends on the client's FY start, so it is not hard-coded either.
--
--  ==> THE CALENDAR IS THE CLIENT'S, NOT THE TENANT'S. <== A Group or Region target spans
--  tenants, so "which practice's financial year" has no answer. The financial year is a client
--  setting (Input.Practice_Config is client-keyed), so one representative tenant supplies the
--  calendar for all of that client's nodes.
--
--  ==> NHS CONTRACT TARGETS GET THEIR OWN BRANCH. <== nhs_udas and nhs_uoas are not typed by
--  anyone -- they are read off the practice's NHS contract -- so they never enter the target grid
--  and cannot come from Fact_Node_Targets. They stay practice-scoped (a UDA contract belongs to
--  one practice) and are apportioned against the CONTRACT's own range, not the client's financial
--  year, because an NHS contract year is April-March regardless and may start or end mid-period.
--
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Load_Aggregate_Period_Targets @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Aggregate_Period_Targets]
GO
CREATE PROCEDURE [Gold].[usp_Load_Aggregate_Period_Targets]
(
      @Mode        VARCHAR(100)     = 'TEST'
    , @Logging     SMALLINT         = 1
    , @Run_UUID    UNIQUEIDENTIFIER = NULL
    , @Run_Inserts BIGINT OUT
    , @Run_Updates BIGINT OUT
    , @Run_Deletes BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0, @My_Updates BIGINT = 0, @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        ---------------------------------------------------------------- one calendar per client
        DROP TABLE IF EXISTS #cal;
        SELECT ct.Client_ID, MIN(ct.Tenant_ID) AS Cal_Tenant_ID
        INTO   #cal
        FROM   [Input].[Client_Tenant] ct
        GROUP BY ct.Client_ID;

        ---------------------------------------------------------------- the live periods only
        -- A grouping is live if its dates reach the latest date any grouping reaches. Exactly the
        -- test /api/filters applies when it decides what to offer.
        DROP TABLE IF EXISTS #latest;
        SELECT c.Client_ID, MAX(d.Full_Date) AS Latest
        INTO   #latest
        FROM   #cal c
        JOIN   [Gold].[Dim_Date_Grouping] g ON g.Tenant_ID = c.Cal_Tenant_ID
        JOIN   [Gold].[Dim_Date] d          ON d.pk_Date   = g.fk_Date
        GROUP BY c.Client_ID;

        -- Which groupings are live, decided at the GROUPING level before anything is split up.
        DROP TABLE IF EXISTS #live;
        SELECT c.Client_ID, g.Date_Grouping
        INTO   #live
        FROM   #cal c
        JOIN   [Gold].[Dim_Date_Grouping] g ON g.Tenant_ID = c.Cal_Tenant_ID
        JOIN   [Gold].[vw_Dim_Date] d       ON d.pk_Date   = g.fk_Date AND d.Tenant_ID = c.Cal_Tenant_ID
        JOIN   #latest l                    ON l.Client_ID = c.Client_ID
        WHERE  d.Is_Weekend = 0 AND d.Is_England_Wales_Bank_Holiday = 0
        GROUP BY c.Client_ID, g.Date_Grouping
        HAVING MAX(d.Full_Date) = MAX(l.Latest);

        -- ==> A ROLLING WINDOW STRADDLES TWO FINANCIAL YEARS, SO IT IS SPLIT BY YEAR. <== This is
        -- the one place the arithmetic is genuinely not a single ratio. Last 12 Months reaches back
        -- across the client's FY boundary, and the two years it touches can carry DIFFERENT annual
        -- targets -- or the metric may be targeted in only one of them. Counting the window's
        -- working days per FY, rather than collapsing it to one year, is what makes the sum below
        -- reproduce the daily explosion it replaced: taking MAX(Financial_Year) instead applied the
        -- later year's target across the whole window, and dropped any metric targeted only in the
        -- earlier one -- which is exactly how this was first found to be wrong.
        DROP TABLE IF EXISTS #wd_pf;
        SELECT c.Client_ID, g.Date_Grouping, d.Financial_Year AS FY, COUNT(*) AS Working_Days
        INTO   #wd_pf
        FROM   #cal c
        JOIN   [Gold].[Dim_Date_Grouping] g ON g.Tenant_ID = c.Cal_Tenant_ID
        JOIN   [Gold].[vw_Dim_Date] d       ON d.pk_Date   = g.fk_Date AND d.Tenant_ID = c.Cal_Tenant_ID
        JOIN   #live lv                     ON lv.Client_ID = c.Client_ID
                                           AND lv.Date_Grouping = g.Date_Grouping
        WHERE  d.Is_Weekend = 0 AND d.Is_England_Wales_Bank_Holiday = 0
        GROUP BY c.Client_ID, g.Date_Grouping, d.Financial_Year;

        DROP TABLE IF EXISTS #wd_fy;
        SELECT c.Client_ID, d.Financial_Year AS FY, COUNT(*) AS Working_Days
        INTO   #wd_fy
        FROM   #cal c
        JOIN   [Gold].[vw_Dim_Date] d ON d.Tenant_ID = c.Cal_Tenant_ID
        WHERE  d.Is_Weekend = 0 AND d.Is_England_Wales_Bank_Holiday = 0
        GROUP BY c.Client_ID, d.Financial_Year;

        ---------------------------------------------------------------- rebuild
        DELETE FROM [Gold].[Aggregate_Period_Targets];
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO [Gold].[Aggregate_Period_Targets]
            (pk_Period_Target, Tenant_ID, Date_Grouping, Metric, Target_Level, Target_Type,
             Target_Value, Variance, Working_Days, DW_Created_At, DW_Updated_At,
             Client_ID, Level_Type, Level_Key)
        SELECT
            ROW_NUMBER() OVER (ORDER BY x.Client_ID, x.Level_Type, x.Level_Key,
                                        x.Date_Grouping, x.Metric, x.Target_Level),
            x.Tenant_ID,
            x.Date_Grouping,
            x.Metric,
            x.Target_Level,
            x.Target_Type,
            x.Target_Value,
            x.Variance,
            x.Working_Days,
            SYSUTCDATETIME(), SYSUTCDATETIME(),
            x.Client_ID, x.Level_Type, x.Level_Key
        FROM (
            -- ==> ONE ROW PER (NODE, PERIOD, METRIC, ROLE), WHATEVER THE PERIOD SPANS. <== The
            -- years are summed HERE rather than left as separate rows, so the grain the model
            -- reads is unchanged and no measure has to care whether its window straddles a year
            -- end. Measures use MAX on some metrics and SUM on others; emitting a row per year
            -- would quietly halve the MAX ones.
            SELECT nt.Client_ID, nt.Level_Type, nt.Level_Key,
                   MAX(ISNULL(nt.Tenant_ID, -1)) AS Tenant_ID,   -- -1 above a practice: no tenant
                   p.Date_Grouping, nt.Metric, nt.Target_Level,
                   ISNULL(cmd.Target_Type, 'cumulative') AS Target_Type,
                   -- A cumulative target earns the share of each financial year the window covers,
                   -- summed. Anything else is a threshold: it reads the same through any window,
                   -- and across a year end the stricter of the two stands -- which is what the
                   -- retired loader's MAX(Annual_Target_Value) did.
                   CAST(CASE WHEN ISNULL(cmd.Target_Type, 'cumulative') = 'cumulative'
                             THEN SUM(nt.Target_Value * (CAST(p.Working_Days AS DECIMAL(18,6))
                                                         / NULLIF(f.Working_Days, 0)))
                             ELSE MAX(nt.Target_Value)
                        END AS DECIMAL(18,4)) AS Target_Value,
                   MAX(mv.Variance) AS Variance,
                   SUM(p.Working_Days) AS Working_Days
            FROM   [Gold].[Fact_Node_Targets] nt
            JOIN   #wd_pf p  ON p.Client_ID = nt.Client_ID AND p.FY = nt.FY
            JOIN   #wd_fy  f ON f.Client_ID = nt.Client_ID AND f.FY = nt.FY
            LEFT  JOIN [Config].[Metric_Definitions] cmd ON cmd.Metric_Key = nt.Metric
            -- The variance band is the client's, like the target it belongs to.
            LEFT  JOIN [Input].[Metric_Variance] mv ON mv.Client_ID = nt.Client_ID
                                                   AND mv.Metric = nt.Metric
            WHERE  nt.Target_Value IS NOT NULL
            GROUP BY nt.Client_ID, nt.Level_Type, nt.Level_Key, p.Date_Grouping,
                     nt.Metric, nt.Target_Level, ISNULL(cmd.Target_Type, 'cumulative')
        ) x;
        SET @My_Inserts = @@ROWCOUNT;

        ---------------------------------------------------------------- NHS contract targets
        -- ==> THESE DO NOT COME FROM THE TARGET GRID, AND CANNOT. <== nhs_udas and nhs_uoas are
        -- never typed by anyone: they are the UDA/UOA counts written into the practice's NHS
        -- contract. So they are absent from Input.Targets, absent from Config.Metric_Definitions,
        -- and therefore absent from Gold.Fact_Node_Targets, which is built from what was entered.
        -- Six live measures read them -- NHS UDAs Target / vs Target / BG and the UOA three --
        -- every one filtering Target Level = 'Practice'. Without this branch all six read blank.
        --
        -- ==> THE CONTRACT CARRIES ITS OWN YEAR, SO IT IS ITS OWN DENOMINATOR. <== An NHS
        -- contract year is April-March whatever the client's financial year is, and a contract can
        -- start or end mid-period. Apportioning against the CLIENT's FY would therefore be wrong
        -- twice over. Instead the ratio is taken against the contract's own range:
        --
        --      target in period = contract total x (working days shared with the period)
        --                                        / (working days in the contract)
        --
        -- which is exactly what the daily explosion summed to, without the 243k rows. A contract
        -- overlapping only part of a rolling window contributes only its overlapping share, which
        -- is the behaviour the old table had and the reason the figure is not simply the annual.
        --
        -- ==> THE CALENDAR IS THE TENANT'S HERE, NOT THE CLIENT'S. <== A UDA contract belongs to
        -- one practice, so there is no group figure to derive and no question about whose year it
        -- is. That also sidesteps a trap: Gold.vw_Dim_Date labels an April-March year by its END
        -- year (FY2026 = Apr 2025 - Mar 2026) while the retired daily loader labelled the same
        -- contract year by its START year. Nothing here joins on an FY label, so the two
        -- conventions cannot collide.
        DROP TABLE IF EXISTS #nhs;
        SELECT fc.Tenant_ID, ct.Client_ID, fc.Start_Date, fc.End_Date,
               CAST(fc.UDA_Target AS DECIMAL(18,4)) AS UDA_Target,
               CAST(fc.UOA_Target AS DECIMAL(18,4)) AS UOA_Target
        INTO   #nhs
        FROM   [Gold].[Fact_Contracts] fc
        JOIN   [Input].[Client_Tenant] ct ON ct.Tenant_ID = fc.Tenant_ID
        WHERE  fc.UDA_Target > 0 OR fc.UOA_Target > 0;

        -- Working days inside the contract (the denominator), and inside each live period that
        -- the contract overlaps (the numerator). Both counted off the practice's own calendar.
        DROP TABLE IF EXISTS #nhs_den;
        SELECT n.Tenant_ID, n.Start_Date, COUNT(*) AS Contract_Days
        INTO   #nhs_den
        FROM   #nhs n
        JOIN   [Gold].[vw_Dim_Date] d ON d.Tenant_ID = n.Tenant_ID
                                     AND d.Full_Date BETWEEN n.Start_Date AND n.End_Date
        WHERE  d.Is_Weekend = 0 AND d.Is_England_Wales_Bank_Holiday = 0
        GROUP BY n.Tenant_ID, n.Start_Date;

        DROP TABLE IF EXISTS #nhs_num;
        SELECT n.Tenant_ID, n.Start_Date, g.Date_Grouping, COUNT(*) AS Shared_Days
        INTO   #nhs_num
        FROM   #nhs n
        JOIN   [Gold].[Dim_Date_Grouping] g ON g.Tenant_ID = n.Tenant_ID
        JOIN   [Gold].[vw_Dim_Date] d       ON d.pk_Date = g.fk_Date AND d.Tenant_ID = n.Tenant_ID
        -- the same live-period test the main branch uses, so the two cannot offer different periods
        JOIN   #live p ON p.Client_ID = n.Client_ID AND p.Date_Grouping = g.Date_Grouping
        WHERE  d.Is_Weekend = 0 AND d.Is_England_Wales_Bank_Holiday = 0
          AND  d.Full_Date BETWEEN n.Start_Date AND n.End_Date
        GROUP BY n.Tenant_ID, n.Start_Date, g.Date_Grouping;

        INSERT INTO [Gold].[Aggregate_Period_Targets]
            (pk_Period_Target, Tenant_ID, Date_Grouping, Metric, Target_Level, Target_Type,
             Target_Value, Variance, Working_Days, DW_Created_At, DW_Updated_At,
             Client_ID, Level_Type, Level_Key)
        SELECT
            (SELECT ISNULL(MAX(pk_Period_Target), 0) FROM [Gold].[Aggregate_Period_Targets])
                + ROW_NUMBER() OVER (ORDER BY x.Tenant_ID, x.Date_Grouping, x.Metric),
            x.Tenant_ID,
            x.Date_Grouping,
            x.Metric,
            'Practice',                       -- a contract is a practice's; the measures filter on this
            'cumulative',                     -- UDAs accumulate through the year
            x.Target_Value,
            mv.Variance,
            x.Shared_Days,
            SYSUTCDATETIME(), SYSUTCDATETIME(),
            x.Client_ID, 'Practice', CAST(x.Tenant_ID AS VARCHAR(64))
        FROM (
            -- A practice holding two contracts that both touch a period contributes both shares,
            -- which is what summing the explosion did.
            SELECT n.Tenant_ID, n.Client_ID, u.Date_Grouping, u.Metric,
                   CAST(SUM(u.Total * (CAST(u.Shared_Days AS DECIMAL(18,6))
                                       / NULLIF(u.Contract_Days, 0))) AS DECIMAL(18,4)) AS Target_Value,
                   SUM(u.Shared_Days) AS Shared_Days
            FROM   #nhs n
            CROSS  APPLY (
                SELECT 'nhs_udas' AS Metric, n.UDA_Target AS Total, nn.Shared_Days,
                       dn.Contract_Days, nn.Date_Grouping
                FROM   #nhs_num nn
                JOIN   #nhs_den dn ON dn.Tenant_ID = n.Tenant_ID AND dn.Start_Date = n.Start_Date
                WHERE  nn.Tenant_ID = n.Tenant_ID AND nn.Start_Date = n.Start_Date
                  AND  n.UDA_Target > 0
                UNION ALL
                SELECT 'nhs_uoas', n.UOA_Target, nn.Shared_Days, dn.Contract_Days, nn.Date_Grouping
                FROM   #nhs_num nn
                JOIN   #nhs_den dn ON dn.Tenant_ID = n.Tenant_ID AND dn.Start_Date = n.Start_Date
                WHERE  nn.Tenant_ID = n.Tenant_ID AND nn.Start_Date = n.Start_Date
                  AND  n.UOA_Target > 0
            ) u
            GROUP BY n.Tenant_ID, n.Client_ID, u.Date_Grouping, u.Metric
        ) x
        LEFT  JOIN [Input].[Metric_Variance] mv ON mv.Client_ID = x.Client_ID AND mv.Metric = x.Metric
        -- An entered target always wins, exactly as the retired loader's priority rule had it.
        WHERE  NOT EXISTS (SELECT 1 FROM [Gold].[Aggregate_Period_Targets] a
                           WHERE a.Client_ID     = x.Client_ID
                             AND a.Level_Type    = 'Practice'
                             AND a.Level_Key     = CAST(x.Tenant_ID AS VARCHAR(64))
                             AND a.Date_Grouping = x.Date_Grouping
                             AND a.Metric        = x.Metric
                             AND a.Target_Level  = 'Practice');
        SET @My_Inserts = @My_Inserts + @@ROWCOUNT;

        DROP TABLE IF EXISTS #nhs; DROP TABLE IF EXISTS #nhs_den; DROP TABLE IF EXISTS #nhs_num;

        DROP TABLE IF EXISTS #cal; DROP TABLE IF EXISTS #latest;
        DROP TABLE IF EXISTS #live; DROP TABLE IF EXISTS #wd_pf; DROP TABLE IF EXISTS #wd_fy;

        SET @Run_Inserts = @My_Inserts; SET @Run_Updates = @My_Updates; SET @Run_Deletes = @My_Deletes;

        IF @Logging = 1
            EXEC [Audit].[ETL_Log_Record_Counts] @Run_UUID = @Run_UUID,
                 @Process_Name = 'Gold.usp_Load_Aggregate_Period_Targets',
                 @Table_Name = 'Gold.Aggregate_Period_Targets',
                 @Rows_Inserted = @My_Inserts, @Rows_Updated = @My_Updates, @Rows_Deleted = @My_Deletes;
    END TRY
    BEGIN CATCH
        EXEC [Audit].[ETL_Error_Handler] @Run_UUID = @Run_UUID,
             @Process_Name = 'Gold.usp_Load_Aggregate_Period_Targets';
        THROW;
    END CATCH
END
GO
