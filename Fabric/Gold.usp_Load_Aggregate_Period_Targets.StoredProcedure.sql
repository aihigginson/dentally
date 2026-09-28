--DECLARE @i BIGINT=0,@u BIGINT=0,@d BIGINT=0; EXEC [Gold].[usp_Load_Aggregate_Period_Targets] @Mode='PROD',@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Period_Targets
--  Author           :  AIH
--  Initial Date     :  28/09/2026
--  Notes:
--    Grain   : one row per (Tenant, Date_Grouping, Metric, Target_Level).
--    Pattern : full rebuild (DELETE + INSERT), pk from ROW_NUMBER().
--    Sources : Gold.Fact_Daily_Targets, Gold.Dim_Date_Grouping, Config.Metric_Definitions.
--
--    ==> THIS IS THE SAME ARITHMETIC THE DAX WAS DOING, DONE ONCE INSTEAD OF PER TILE. <==
--    The target measures scanned 243,252 daily rows per tile per render. The period is always
--    one named grouping, so the answer can be computed here: 1,296 rows, looked up.
--
--    ==> THE SPLIT BY Target_Type IS THE WHOLE CORRECTNESS RISK. <== A cumulative target
--    accumulates across the period (so a part-period gets its prorated share) while a rate or
--    a snapshot does not -- summing a ratio across 366 days would produce nonsense. This
--    mirrors Config.Metric_Definitions.Target_Type, which is the same thing the DAX builders
--    keyed off (tCumFTE/tEffRunRate summed Daily_Target_Value; tRate/tEff took MAX of
--    Annual_Target_Value). The release guard proves the two agree rather than trusting it.
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

        DELETE FROM [Gold].[Aggregate_Period_Targets];
        SET @My_Deletes = @@ROWCOUNT;

        -- Every (grouping, metric, level) the daily fact can answer for, aggregated the way that
        -- metric's Target_Type says it must be. Target_Type is LEFT JOINed and defaulted to
        -- 'cumulative': an unregistered metric keeps the accumulating behaviour it had before,
        -- rather than silently switching to a threshold.
        INSERT INTO [Gold].[Aggregate_Period_Targets]
            (pk_Period_Target, Tenant_ID, Date_Grouping, Metric, Target_Level, Target_Type,
             Target_Value, Variance, Working_Days, DW_Created_At, DW_Updated_At)
        SELECT
            ROW_NUMBER() OVER (ORDER BY g.Tenant_ID, g.Date_Grouping, t.Metric, t.Target_Level),
            g.Tenant_ID,
            g.Date_Grouping,
            t.Metric,
            t.Target_Level,
            ISNULL(c.Target_Type, 'cumulative'),
            CASE WHEN ISNULL(c.Target_Type, 'cumulative') = 'cumulative'
                 THEN SUM(t.Daily_Target_Value)          -- accumulates: prorated by definition
                 ELSE MAX(t.Annual_Target_Value)         -- a threshold: never accumulates
            END,
            MAX(t.Variance),                             -- a band, not a quantity
            COUNT(*),
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM [Gold].[Dim_Date_Grouping] g
        JOIN [Gold].[Fact_Daily_Targets] t
               ON t.Tenant_ID = g.Tenant_ID AND t.fk_Date = g.fk_Date
        LEFT JOIN [Config].[Metric_Definitions] c
               ON c.Metric_Key = t.Metric
        GROUP BY g.Tenant_ID, g.Date_Grouping, t.Metric, t.Target_Level,
                 ISNULL(c.Target_Type, 'cumulative');
        SET @My_Inserts = @@ROWCOUNT;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes
END
GO
