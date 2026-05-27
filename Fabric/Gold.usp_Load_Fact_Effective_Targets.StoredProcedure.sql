--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Effective_Targets] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Effective_Targets
--  Author           :  AIH
--  Initital Date    :  27/05/2026
--  History          :
--    *01     27/05/2026  AIH Initial Release
--
--  Purpose          :  Pre-resolves site vs practice target precedence so DAX
--                      measures can use a single CALCULATE(MAX(...)) lookup
--                      instead of nested COALESCE(MAXX(FILTER(...))) calls.
--
--                      Produces one row per (Tenant, Site, Metric, Period):
--                        fk_Practice_Site = -1  : practice-level (all sites)
--                        fk_Practice_Site = pk  : site-specific if a row exists
--                                                 in Input.Targets for that site,
--                                                 otherwise falls back to the
--                                                 practice-level value.
--
--  Dependencies     :  Gold.usp_Load_Fact_Targets must run first.
--
--  To Run           :  DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT;
--                      EXEC Gold.usp_Load_Fact_Effective_Targets
--                           @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Effective_Targets]    Script Date: 27/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Effective_Targets]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Effective_Targets]
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

        DROP TABLE IF EXISTS [Gold].[Fact_Effective_Targets];

        CREATE TABLE [Gold].[Fact_Effective_Targets] (
            [pk_Effective_Target]   BIGINT IDENTITY NOT NULL,
            [Tenant_ID]             INT           NOT NULL,
            [fk_Practice_Site]      BIGINT        NOT NULL,
            [Metric]                VARCHAR(100)  NOT NULL,
            [Period_Type]           VARCHAR(20)   NOT NULL,
            [Period_Value]          VARCHAR(20)   NOT NULL,
            [Effective_Target]      DECIMAL(18,4) NOT NULL,
            [Effective_Variance]    DECIMAL(10,4) NULL
        );

        INSERT INTO [Gold].[Fact_Effective_Targets] (
            Tenant_ID, fk_Practice_Site, Metric, Period_Type, Period_Value,
            Effective_Target, Effective_Variance
        )
        -- Practice-level rows: pass through as-is (fk_Practice_Site = -1)
        SELECT
            Tenant_ID,
            -1,
            Metric,
            Period_Type,
            Period_Value,
            Target_Value,
            Variance
        FROM [Gold].[Fact_Targets]
        WHERE fk_Practice_Site = -1

        UNION ALL

        -- Site-level rows: use site-specific target if one exists in Input.Targets,
        -- otherwise inherit the practice-level value.
        SELECT
            dps.Tenant_ID,
            dps.pk_Practice_Site,
            p.Metric,
            p.Period_Type,
            p.Period_Value,
            COALESCE(s.Target_Value, p.Target_Value),
            COALESCE(s.Variance,     p.Variance)
        FROM [Gold].[Dim_Practice_Sites]  dps
        JOIN [Gold].[Fact_Targets]        p
            ON  p.Tenant_ID        = dps.Tenant_ID
            AND p.fk_Practice_Site = -1            -- practice-level row to expand
        LEFT JOIN [Gold].[Fact_Targets]   s
            ON  s.Tenant_ID        = dps.Tenant_ID
            AND s.fk_Practice_Site = dps.pk_Practice_Site
            AND s.Metric           = p.Metric
            AND s.Period_Type      = p.Period_Type
            AND s.Period_Value     = p.Period_Value;

        SET @My_Inserts = @@ROWCOUNT;

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
