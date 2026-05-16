--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Targets] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Targets
--  Author           :  AIH
--  Initital Date    :  06/05/2026
--  History          :
--    *01     06/05/2026  AIH Initial Release
--    *02     06/05/2026  AIH Add all_time period type (no date key — fk_Date uses -1 sentinel)
--  To Run           :  DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_Targets @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Targets]    Script Date: 06/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Targets]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Targets]
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

        SELECT
            t.[Tenant_ID]                                               AS Tenant_ID,
            t.[pk_target]                                               AS bk_target_id,

            ISNULL(dps.[pk_Practice_Site], -1)                         AS fk_Practice_Site,
            ISNULL(dpr.[pk_Practitioner],  -1)                         AS fk_Practitioner,
            ISNULL(dd.[pk_Date],           -1)                         AS fk_Date,

            t.[Metric]                                                  AS Metric,
            t.[Period_Type]                                             AS Period_Type,
            t.[Period_Value]                                            AS Period_Value,
            t.[Target_Value]                                            AS Target_Value

        INTO #src
        FROM [Input].[Targets] t

        LEFT JOIN [Gold].[Dim_Practice_Sites] dps
            ON  dps.[Site_ID]   = t.[Site_ID]
            AND dps.[Tenant_ID] = t.[Tenant_ID]

        LEFT JOIN [Gold].[Dim_Practitioners] dpr
            ON  dpr.[Practitioner_ID] = t.[Practitioner_ID]
            AND dpr.[Tenant_ID]       = t.[Tenant_ID]

        LEFT JOIN [Gold].[Dim_Date] dd
            ON  dd.[Full_Date] = CASE t.[Period_Type]
                    WHEN 'financial_year' THEN
                        -- 'FY 2025/26' -> 2025-04-01  (UK financial year starts April)
                        DATEFROMPARTS(CAST(SUBSTRING(t.[Period_Value], 4, 4) AS INT), 4, 1)
                    WHEN 'monthly' THEN
                        -- '2026-04' -> 2026-04-01
                        DATEFROMPARTS(CAST(LEFT(t.[Period_Value], 4) AS INT),
                                      CAST(RIGHT(t.[Period_Value], 2) AS INT), 1)
                    WHEN 'all_time' THEN
                        -- No specific date; ISNULL resolves to fk_Date = -1 sentinel
                        NULL
                    END;

        -- Remove rows no longer in Input
        DELETE tgt
        FROM [Gold].[Fact_Targets] tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src
            WHERE bk_target_id = tgt.[bk_target_id]
            AND   Tenant_ID    = tgt.[Tenant_ID]
        );
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Practice_Site = src.fk_Practice_Site,
            fk_Practitioner  = src.fk_Practitioner,
            fk_Date          = src.fk_Date,
            Metric           = src.Metric,
            Period_Type      = src.Period_Type,
            Period_Value     = src.Period_Value,
            Target_Value     = src.Target_Value,
            DW_Updated_At    = SYSUTCDATETIME()
        FROM [Gold].[Fact_Targets] tgt
        INNER JOIN #src src
            ON  tgt.[bk_target_id] = src.bk_target_id
            AND tgt.[Tenant_ID]    = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
            ISNULL(CAST(tgt.[fk_Practice_Site] AS VARCHAR(50)), ''),
            ISNULL(CAST(tgt.[fk_Practitioner]  AS VARCHAR(50)), ''),
            ISNULL(CAST(tgt.[fk_Date]          AS VARCHAR(50)), ''),
            ISNULL(CAST(tgt.[Target_Value]     AS VARCHAR(50)), ''),
            ISNULL(tgt.[Metric],      ''),
            ISNULL(tgt.[Period_Type], ''),
            ISNULL(tgt.[Period_Value],'')
        )) <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
            ISNULL(CAST(src.[fk_Practice_Site] AS VARCHAR(50)), ''),
            ISNULL(CAST(src.[fk_Practitioner]  AS VARCHAR(50)), ''),
            ISNULL(CAST(src.[fk_Date]          AS VARCHAR(50)), ''),
            ISNULL(CAST(src.[Target_Value]     AS VARCHAR(50)), ''),
            ISNULL(src.[Metric],      ''),
            ISNULL(src.[Period_Type], ''),
            ISNULL(src.[Period_Value],'')
        ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO [Gold].[Fact_Targets] (
            Tenant_ID, bk_target_id,
            fk_Practice_Site, fk_Practitioner, fk_Date,
            Metric, Period_Type, Period_Value, Target_Value,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID, src.bk_target_id,
            src.fk_Practice_Site, src.fk_Practitioner, src.fk_Date,
            src.Metric, src.Period_Type, src.Period_Value, src.Target_Value,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Gold].[Fact_Targets] tgt
            WHERE tgt.[bk_target_id] = src.bk_target_id
            AND   tgt.[Tenant_ID]    = src.Tenant_ID
        );
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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
