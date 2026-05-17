--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Daily_Targets] @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Daily_Targets
--  Author           :  AIH
--  Initital Date    :  17/05/2026
--  History          :
--    *01     17/05/2026  AIH Initial Release
--  To Run           :  DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_Daily_Targets @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
--
--  Purpose:
--    Explodes annual targets from Input.Targets into one row per working day
--    (Mon-Fri, excluding England & Wales bank holidays) for each financial year.
--    Daily_Target_Value = annual Target_Value / working days in that financial year.
--    Variance band carries through unchanged (it is a % threshold, not a value).
--    The resulting table is intended to be joined to Dim_Date in PBI so that any
--    date filter context automatically sums the correct proportional target with
--    no DAX proration logic required.
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

        -- Count working days per financial year.
        -- Cast to varchar to avoid char(9) collation edge cases in temp tables.
        SELECT
            CAST(Financial_Year_Name AS varchar(9)) AS FY_Name,
            COUNT(*)                                AS Working_Days
        INTO #wd
        FROM [Gold].[Dim_Date]
        WHERE [Is_Weekend]                    = 0
          AND [Is_England_Wales_Bank_Holiday] = 0
        GROUP BY Financial_Year_Name;

        -- Full reload: remove all existing daily target rows
        DELETE FROM [Gold].[Fact_Daily_Targets];
        SET @My_Deletes = @@ROWCOUNT;

        -- Insert one row per metric per working day.
        -- Joins Input.Targets (annual rows) to the working-day spine via FY name.
        -- REPLACE strips the space in 'FY 2026/27' to match char(9) 'FY2026/27'.
        -- Only Period_Type = 'annual' or 'financial_year' rows are exploded;
        -- 'monthly' and 'all_time' rows in Input.Targets are left to Fact_Targets.
        INSERT INTO [Gold].[Fact_Daily_Targets] (
            Tenant_ID, Site_ID, Practitioner_ID,
            fk_Date, Metric,
            Daily_Target_Value, Variance,
            DW_Created_At
        )
        SELECT
            t.[Tenant_ID],
            t.[Site_ID],
            t.[Practitioner_ID],
            d.[pk_Date],
            t.[Metric],
            t.[Target_Value] / CAST(w.Working_Days AS DECIMAL(10,0)),
            t.[Variance],
            SYSUTCDATETIME()
        FROM [Input].[Targets] t
        INNER JOIN [Config].[Metric_Definitions] cmd
            ON  cmd.[Metric_Key]  = t.[Metric]
            AND cmd.[Target_Type] = 'cumulative'
        INNER JOIN #wd w
            ON REPLACE(t.[Period_Value], ' ', '') = w.FY_Name
        INNER JOIN [Gold].[Dim_Date] d
            ON d.[Financial_Year_Name]            = w.FY_Name
            AND d.[Is_Weekend]                    = 0
            AND d.[Is_England_Wales_Bank_Holiday] = 0
        WHERE t.[Period_Type] IN ('annual', 'financial_year');

        SET @My_Inserts = @@ROWCOUNT;

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
