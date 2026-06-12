--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Daily_Targets] @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Daily_Targets
--  Author           :  AIH
--  Initital Date    :  17/05/2026
--  History          :
--    *01     17/05/2026  AIH Initial Release
--    *02     18/05/2026  AIH Rework explosion logic: all_time targets apply to
--                            all FYs in Dim_Date; specific FY rows override.
--                            Ensures one daily-rate row per working day per FY
--                            regardless of how the target was entered.
--    *03     18/05/2026  AIH Bound all_time CROSS JOIN to 2 FYs back, current FY,
--                            1 FY forward (dynamic, relative to run date).
--    *04     27/05/2026  AIH Standardise FY format to 'FY 2025-26'; remove multi-format
--                            join conditions.
--    *05     27/05/2026  AIH Replace Site_ID with fk_Practice_Site (surrogate key,
--                            -1 = practice level) so PBI filter context works.
--    *06     27/05/2026  AIH Replace Practitioner_ID with fk_Practitioner (surrogate
--                            key, -1 = no practitioner) for consistency.
--    *07     29/05/2026  AIH Add nhs_udas / nhs_uoas from Gold.Fact_Contracts at
--                            Priority 2; shift all_time fallback to Priority 3.
--  To Run           :  DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_Daily_Targets @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
--
--  Purpose:
--    Explodes cumulative targets from Input.Targets into one row per working day
--    (Mon-Fri, excluding England & Wales bank holidays) for each financial year.
--    Daily_Target_Value = Target_Value / working days in that financial year.
--    Variance band carries through unchanged (it is a % threshold, not a value).
--
--    Target resolution per (Tenant, Site, Practitioner, Metric, FY):
--      Priority 1 — specific FY row  (Period_Type = 'annual' / 'financial_year',
--                                     Period_Value matches the FY, e.g. 'FY 2026/27')
--      Priority 2 — all_time fallback (Period_Type = 'all_time', applied to every FY)
--
--    This means a single all_time target row covers all historical and future years.
--    Per-FY overrides can be added later without touching the fallback.
--
--    YTD accuracy: DAX SUMs only the working-day rows within the active date filter,
--    so selecting April 1 to today automatically gives the correct YTD target with
--    no additional proration logic.
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Daily_Targets]    Script Date: 17/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Daily_Targets]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Daily_Targets]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       SMALLINT         = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        -- FY range for all_time expansion: 2 full FYs back, current FY, 1 FY forward.
        DECLARE @Cur_FY_Year SMALLINT = CASE WHEN MONTH(CAST(SYSUTCDATETIME() AS DATE)) >= 4
                                             THEN YEAR(CAST(SYSUTCDATETIME() AS DATE))
                                             ELSE YEAR(CAST(SYSUTCDATETIME() AS DATE)) - 1 END;
        DECLARE @FY_Min VARCHAR(10) = 'FY ' + CAST(@Cur_FY_Year - 2 AS VARCHAR(4)) + '-' + RIGHT(CAST(@Cur_FY_Year - 1 AS VARCHAR(4)), 2);
        DECLARE @FY_Max VARCHAR(10) = 'FY ' + CAST(@Cur_FY_Year + 1 AS VARCHAR(4)) + '-' + RIGHT(CAST(@Cur_FY_Year + 2 AS VARCHAR(4)), 2);

        -- Working day counts per financial year (all FYs in the date table).
        SELECT
            CAST(Financial_Year_Name AS varchar(10)) AS FY_Name,
            COUNT(*)                                AS Working_Days
        INTO #wd
        FROM [Gold].[Dim_Date]
        WHERE [Is_Weekend]                    = 0
          AND [Is_England_Wales_Bank_Holiday] = 0
        GROUP BY Financial_Year_Name;

        -- Build candidate target rows: one per (Tenant, Site, Practitioner, Metric, FY).
        -- Priority 1 = specific FY target; Priority 2 = all_time fallback.
        -- CROSS JOIN for all_time is bounded to @FY_Min/@FY_Max (2 back, current, 1 forward).
        SELECT
            t.[Tenant_ID],
            ISNULL(t.[Site_ID], '')         AS Site_ID,
            ISNULL(t.[Practitioner_ID], -1) AS Practitioner_ID,
            t.[Metric],
            w.FY_Name,
            t.[Target_Value],
            t.[Variance],
            1                               AS Priority
        INTO #candidates
        FROM [Input].[Targets] t
        INNER JOIN [Config].[Metric_Definitions] cmd
            ON  cmd.[Metric_Key]  = t.[Metric]
            AND cmd.[Target_Type] = 'cumulative'
        INNER JOIN #wd w
            ON  w.FY_Name = t.[Period_Value]
        WHERE t.[Period_Type] IN ('annual', 'financial_year')

        UNION ALL

        SELECT
            t.[Tenant_ID],
            ISNULL(t.[Site_ID], '')         AS Site_ID,
            ISNULL(t.[Practitioner_ID], -1) AS Practitioner_ID,
            t.[Metric],
            w.FY_Name,
            t.[Target_Value],
            t.[Variance],
            3                               AS Priority
        FROM [Input].[Targets] t
        INNER JOIN [Config].[Metric_Definitions] cmd
            ON  cmd.[Metric_Key]  = t.[Metric]
            AND cmd.[Target_Type] = 'cumulative'
        CROSS JOIN #wd w
        WHERE t.[Period_Type] = 'all_time'
          AND w.FY_Name BETWEEN @FY_Min AND @FY_Max;

        -- NHS UDA / UOA annual targets derived from contracted values.
        -- Priority 2: wins over all_time fallback; loses to a manual annual
        --             Input.Targets row for the same metric/FY/site (Priority 1).
        -- Contracts can span multiple years (e.g. 2023-04-01 to 2027-03-31);
        -- each FY within the contract date range gets the same UDA/UOA target value.
        -- FY start year extracted from FY_Name 'FY YYYY-YY' via SUBSTRING(w.FY_Name,4,4).
        INSERT INTO #candidates (Tenant_ID, Site_ID, Practitioner_ID, Metric, FY_Name, Target_Value, Variance, Priority)
        SELECT
            fc.Tenant_ID,
            ISNULL(fc.Site_ID, '')  AS Site_ID,
            -1                      AS Practitioner_ID,
            'nhs_udas'              AS Metric,
            w.FY_Name,
            fc.UDA_Target           AS Target_Value,
            10                      AS Variance,
            2                       AS Priority
        FROM Gold.Fact_Contracts fc
        INNER JOIN #wd w
            ON  CAST(SUBSTRING(w.FY_Name, 4, 4) AS INT) >= YEAR(fc.Start_Date)
            AND CAST(SUBSTRING(w.FY_Name, 4, 4) AS INT) <=
                CASE WHEN MONTH(fc.End_Date) <= 3
                     THEN YEAR(fc.End_Date) - 1
                     ELSE YEAR(fc.End_Date) END
        WHERE fc.UDA_Target > 0

        UNION ALL

        SELECT
            fc.Tenant_ID,
            ISNULL(fc.Site_ID, ''),
            -1,
            'nhs_uoas',
            w.FY_Name,
            fc.UOA_Target,
            10,
            2
        FROM Gold.Fact_Contracts fc
        INNER JOIN #wd w
            ON  CAST(SUBSTRING(w.FY_Name, 4, 4) AS INT) >= YEAR(fc.Start_Date)
            AND CAST(SUBSTRING(w.FY_Name, 4, 4) AS INT) <=
                CASE WHEN MONTH(fc.End_Date) <= 3
                     THEN YEAR(fc.End_Date) - 1
                     ELSE YEAR(fc.End_Date) END
        WHERE fc.UOA_Target > 0;

        -- Pick the highest-priority target per (Tenant, Site, Practitioner, Metric, FY).
        SELECT
            Tenant_ID, Site_ID, Practitioner_ID, Metric, FY_Name, Target_Value, Variance
        INTO #best
        FROM (
            SELECT *,
                ROW_NUMBER() OVER (
                    PARTITION BY Tenant_ID, Site_ID, Practitioner_ID, Metric, FY_Name
                    ORDER BY Priority
                ) AS rn
            FROM #candidates
        ) x
        WHERE rn = 1;

        -- Full reload.
        DELETE FROM [Gold].[Fact_Daily_Targets];
        SET @My_Deletes = @@ROWCOUNT;

        -- Insert one row per working day per resolved target.
        INSERT INTO [Gold].[Fact_Daily_Targets] (
            Tenant_ID, fk_Practice_Site, fk_Practitioner,
            fk_Date, Metric,
            Daily_Target_Value, Variance,
            DW_Created_At
        )
        SELECT
            b.Tenant_ID,
            ISNULL(dps.pk_Practice_Site, -1),
            ISNULL(dp.pk_Practitioner,   -1),
            d.[pk_Date],
            b.Metric,
            b.Target_Value / CAST(w.Working_Days AS DECIMAL(10,0)),
            b.Variance,
            SYSUTCDATETIME()
        FROM #best b
        INNER JOIN #wd w
            ON b.FY_Name = w.FY_Name
        INNER JOIN [Gold].[Dim_Date] d
            ON d.[Financial_Year_Name]            = w.FY_Name
            AND d.[Is_Weekend]                    = 0
            AND d.[Is_England_Wales_Bank_Holiday] = 0
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps
            ON  dps.Tenant_ID = b.Tenant_ID
            AND dps.Site_ID   = NULLIF(b.Site_ID, '')
        LEFT JOIN [Gold].[Dim_Practitioners] dp
            ON  dp.Tenant_ID       = b.Tenant_ID
            AND dp.Practitioner_ID = NULLIF(b.Practitioner_ID, -1);

        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #candidates;
        DROP TABLE #best;
        DROP TABLE #wd;

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
