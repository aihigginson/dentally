--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Treatment_Appointments] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Treatment_Appointments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Wrap non-date FK lookups with ISNULL(..., -1) for unknown dimension row
--    *03     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *04     22/05/2026  AIH Add Tenant_ID filter to Silver.Appointments join to prevent cross-tenant duplicate rows
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Fact_Treatment_Appointments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Treatment_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Treatment_Appointments]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Treatment_Appointments]
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

        SELECT
            ta.Tenant_ID                                                AS Tenant_ID,
            ta.Id                                                       AS bk_Treatment_Appointment_ID,
            ISNULL(dpat.pk_Patient, -1)                                 AS fk_Patient,
            ISNULL(dtp.pk_Treatment_Plan, -1)                           AS fk_Treatment_Plan,
            dd_a.pk_Date                                                AS fk_Date_Appointment,
            dd_c.pk_Date                                                AS fk_Date_Created,
            ta.Appointment_ID                                           AS Appointment_ID,
            ta.Treatment_Plan_ID                                        AS Treatment_Plan_ID,
            ta.Position                                                 AS Position,
            ta.Bookable                                                 AS Bookable,
            CAST(NULL AS datetime2(3))                                  AS Created_At,
            CAST(NULL AS datetime2(3))                                  AS Updated_At
        INTO #src
        FROM Silver.Treatment_Appointments ta
        LEFT JOIN Gold.Dim_Patients dpat        ON dpat.Patient_ID        = ta.Patient_ID        AND dpat.Tenant_ID = ta.Tenant_ID
        LEFT JOIN Gold.Dim_Treatment_Plans dtp  ON dtp.Treatment_Plan_ID  = ta.Treatment_Plan_ID AND dtp.Tenant_ID = ta.Tenant_ID
        LEFT JOIN Silver.Appointments ba        ON ba.Appointment_ID      = ta.Appointment_ID      AND ba.Tenant_ID = ta.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_a            ON dd_a.Full_Date         = TRY_CAST(NULLIF(TRIM(ba.Start_Time),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_c            ON dd_c.Full_Date         = TRY_CAST(NULLIF(TRIM(ba.Start_Time),'') AS DATE)
        WHERE ta.Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Treatment_Appointments tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Treatment_Appointment_ID = tgt.bk_Treatment_Appointment_ID AND Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Patient              = src.fk_Patient,
            fk_Treatment_Plan       = src.fk_Treatment_Plan,
            fk_Date_Appointment     = src.fk_Date_Appointment,
            fk_Date_Created         = src.fk_Date_Created,
            Appointment_ID          = src.Appointment_ID,
            Treatment_Plan_ID       = src.Treatment_Plan_ID,
            Position                = src.Position,
            Bookable                = src.Bookable,
            Updated_At              = src.Updated_At,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Fact_Treatment_Appointments tgt
        INNER JOIN #src src ON tgt.bk_Treatment_Appointment_ID = src.bk_Treatment_Appointment_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Appointment] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Appointment_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Position] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Bookable] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_At] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Appointment] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Appointment_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Position] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Bookable] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_At] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Treatment_Appointments (
            Tenant_ID,
            bk_Treatment_Appointment_ID,
            fk_Patient, fk_Treatment_Plan,
            fk_Date_Appointment, fk_Date_Created,
            Appointment_ID, Treatment_Plan_ID, Position, Bookable,
            Created_At, Updated_At, DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID,
            src.bk_Treatment_Appointment_ID,
            src.fk_Patient, src.fk_Treatment_Plan,
            src.fk_Date_Appointment, src.fk_Date_Created,
            src.Appointment_ID, src.Treatment_Plan_ID, src.Position, src.Bookable,
            src.Created_At, src.Updated_At, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Treatment_Appointments tgt WHERE tgt.bk_Treatment_Appointment_ID = src.bk_Treatment_Appointment_ID AND tgt.Tenant_ID = src.Tenant_ID);
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
