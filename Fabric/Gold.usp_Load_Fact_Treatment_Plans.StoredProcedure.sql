--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Treatment_Plans] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Treatment_Plans
--  Author           :  AIH
--  Initital Date    :  21/06/2026
--  History          :
--    *01     21/06/2026  AIH Initial Release. Plan-grain fact so plan measures slice by the
--                            PLAN's own practitioner/site/date (not its items'). Resolves
--                            fk_Patient/Practitioner/Practice_Site/Treatment_Plan + fk_Date_*
--                            from Silver.Treatment_Plans. Delete-orphans / hash-update /
--                            insert-new upsert (no watermark; processes all Silver, like the dim).
--  To Run			 :   DECLARE  @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_Treatment_Plans @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Treatment_Plans]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Treatment_Plans]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       smallint      = 1
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

        -- Resolve the plan's OWN dimension keys (practitioner / site / patient / dates) so the
        -- plan-grain measures slice correctly. -1 = unknown (FK guard convention); dates stay
        -- NULL when unparseable (consistent with the other Gold facts).
        SELECT
            tp.Tenant_ID                                                        AS Tenant_ID,
            CAST(tp.Id AS INT)                                                  AS bk_Treatment_Plan_ID,
            ISNULL(dtp.pk_Treatment_Plan, -1)                                   AS fk_Treatment_Plan,
            ISNULL(dpat.pk_Patient, -1)                                         AS fk_Patient,
            ISNULL(dpr.pk_Practitioner, -1)                                     AS fk_Practitioner,
            CAST(-1 AS BIGINT)                                                  AS fk_Practice_Site,  -- Dentally treatment-plan object has NO site -> always unknown (-1)
            dd_c.pk_Date                                                        AS fk_Date_Created,
            dd_s.pk_Date                                                        AS fk_Date_Start,
            dd_comp.pk_Date                                                     AS fk_Date_Completed,
            CAST(ISNULL(tp.Completed,0) AS BIT)                                 AS Completed,
            TRY_CAST(LEFT(NULLIF(TRIM(tp.Start_Date), ''), 10) AS DATE)         AS Start_Date,
            CAST(1 AS INT)                                                      AS Treatment_Plan_Count,
            CAST(ISNULL(tp.NHS_UDA_Value,0) AS DECIMAL(18,4))                   AS NHS_UDA_Value,
            CAST(ISNULL(tp.NHS_Completed_UDA_Value,0) AS DECIMAL(18,4))         AS NHS_Completed_UDA_Value,
            CAST(ISNULL(tp.Private_Treatment_Value,0) AS DECIMAL(18,4))         AS Private_Treatment_Value
        INTO #src
        FROM Silver.Treatment_Plans tp
        LEFT JOIN Gold.Dim_Treatment_Plans dtp ON dtp.Treatment_Plan_ID = CAST(tp.Id AS INT)             AND dtp.Tenant_ID = tp.Tenant_ID
        LEFT JOIN Gold.Dim_Patients dpat       ON dpat.Patient_ID       = CAST(tp.Patient_ID AS INT)     AND dpat.Tenant_ID = tp.Tenant_ID
        LEFT JOIN Gold.Dim_Practitioners dpr   ON dpr.Practitioner_ID   = CAST(tp.Practitioner_ID AS INT) AND dpr.Tenant_ID = tp.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_c           ON dd_c.Full_Date        = TRY_CAST(LEFT(NULLIF(TRIM(tp.Created_At),  ''),10) AS DATE)
        LEFT JOIN Gold.Dim_Date dd_s           ON dd_s.Full_Date        = TRY_CAST(LEFT(NULLIF(TRIM(tp.Start_Date),  ''),10) AS DATE)
        LEFT JOIN Gold.Dim_Date dd_comp        ON dd_comp.Full_Date     = TRY_CAST(LEFT(NULLIF(TRIM(tp.Completed_At),''),10) AS DATE)
        WHERE tp.Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Treatment_Plans tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src s WHERE s.bk_Treatment_Plan_ID = tgt.bk_Treatment_Plan_ID AND s.Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Treatment_Plan       = src.fk_Treatment_Plan,
            fk_Patient              = src.fk_Patient,
            fk_Practitioner         = src.fk_Practitioner,
            fk_Practice_Site        = src.fk_Practice_Site,
            fk_Date_Created         = src.fk_Date_Created,
            fk_Date_Start           = src.fk_Date_Start,
            fk_Date_Completed       = src.fk_Date_Completed,
            Completed               = src.Completed,
            Start_Date              = src.Start_Date,
            NHS_UDA_Value           = src.NHS_UDA_Value,
            NHS_Completed_UDA_Value = src.NHS_Completed_UDA_Value,
            Private_Treatment_Value = src.Private_Treatment_Value,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Fact_Treatment_Plans tgt
        INNER JOIN #src src ON tgt.bk_Treatment_Plan_ID = src.bk_Treatment_Plan_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Treatment_Plan]       AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Patient]              AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practitioner]         AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practice_Site]        AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Created]         AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Start]           AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Completed]       AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Completed]               AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Start_Date]              AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_UDA_Value]           AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Completed_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Private_Treatment_Value] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Treatment_Plan]       AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Patient]              AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practitioner]         AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practice_Site]        AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Created]         AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Start]           AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Completed]       AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Completed]               AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Start_Date]              AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_UDA_Value]           AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Completed_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Private_Treatment_Value] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows (pk_Treatment_Plan_Fact is IDENTITY)
        INSERT INTO Gold.Fact_Treatment_Plans (
            Tenant_ID, bk_Treatment_Plan_ID, fk_Treatment_Plan,
            fk_Patient, fk_Practitioner, fk_Practice_Site,
            fk_Date_Created, fk_Date_Start, fk_Date_Completed,
            Completed, Start_Date, Treatment_Plan_Count,
            NHS_UDA_Value, NHS_Completed_UDA_Value, Private_Treatment_Value,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID, src.bk_Treatment_Plan_ID, src.fk_Treatment_Plan,
            src.fk_Patient, src.fk_Practitioner, src.fk_Practice_Site,
            src.fk_Date_Created, src.fk_Date_Start, src.fk_Date_Completed,
            src.Completed, src.Start_Date, src.Treatment_Plan_Count,
            src.NHS_UDA_Value, src.NHS_Completed_UDA_Value, src.Private_Treatment_Value,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Treatment_Plans tgt WHERE tgt.bk_Treatment_Plan_ID = src.bk_Treatment_Plan_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
        --*********************************
        --**** Procedure logic ends    ****
        --*********************************

    END TRY

    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes

END
GO
