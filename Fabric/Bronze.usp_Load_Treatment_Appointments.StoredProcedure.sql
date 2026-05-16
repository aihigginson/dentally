--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Treatment_Appointments
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Treatment_Appointments]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Treatment_Appointments]
(
      @Tenant_ID    INT
    , @Full_Refresh BIT              = 0
    , @Logging      SMALLINT         = 1
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    DECLARE @My_Run_UUID VARCHAR(36);
    DECLARE @My_Error    VARCHAR(4000);
    SET NOCOUNT ON;
    DECLARE @Proc_Options VARCHAR(1000);
    DECLARE @Parent_UUID  VARCHAR(36);
    SET @Proc_Options = CONCAT('@Tenant_ID = ', CAST(@Tenant_ID AS VARCHAR), ', @Full_Refresh = ', CAST(@Full_Refresh AS INT));
    SET @Parent_UUID  = ISNULL(CONVERT(VARCHAR(36), @Run_UUID), '00000000-0000-0000-0000-000000000000');
    IF @Logging = 1
        EXEC Audit.ETL_Start_Run
            @Run_Process_Name    = 'Bronze.usp_Load_Treatment_Appointments',
            @Run_Process_Options = @Proc_Options,
            @Run_UUID            = @My_Run_UUID OUTPUT,
            @Parent_Run_UUID     = @Parent_UUID;

    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id AS INT)                          AS Tenant_ID
            , LEFT(id, 255)                                       AS ID
            , CASE WHEN bookable IN ('True', '1', 'true') THEN 1 ELSE 0 END AS Bookable
            , LEFT(notes, 4000)                                   AS Notes
            , TRY_CAST(position AS INT)                           AS Position
            , LEFT(created_at, 255)                               AS Created_At
            , LEFT(updated_at, 255)                               AS Updated_At
            , TRY_CAST(appointment_id AS INT)                     AS Appointment_ID
            , TRY_CAST(patient_id AS INT)                         AS Patient_ID
            , TRY_CAST(treatment_plan_id AS INT)                  AS Treatment_Plan_ID
        INTO #src
        FROM Stage.Treatment_Appointments
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Bookable          = src.Bookable
            , tgt.Notes             = src.Notes
            , tgt.Position          = src.Position
            , tgt.Appointment_ID    = src.Appointment_ID
            , tgt.Patient_ID        = src.Patient_ID
            , tgt.Treatment_Plan_ID = src.Treatment_Plan_ID
            , tgt.Updated_At        = src.Updated_At
            , tgt.DW_Loaded_At      = SYSUTCDATETIME()
        FROM Bronze.Treatment_Appointments AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Treatment_Appointments (Tenant_ID, ID, Bookable, Notes, Position, Created_At, Updated_At, Appointment_ID, Patient_ID, Treatment_Plan_ID, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Bookable, src.Notes, src.Position, src.Created_At, src.Updated_At, src.Appointment_ID, src.Patient_ID, src.Treatment_Plan_ID, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Treatment_Appointments tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Treatment_Appointments AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = tgt.ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

        IF @Logging = 1
            EXEC Audit.ETL_Finish_Run
                @Run_UUID      = @My_Run_UUID,
                @Run_Status    = 'SUCCEEDED',
                @Rows_Inserted = @My_Inserts,
                @Rows_Updated  = @My_Updates,
                @Rows_Deleted  = @My_Deletes;
    END TRY
    BEGIN CATCH
        IF @Logging = 1
        BEGIN
            SET @My_Error = Audit.ETL_Error_Handler();
            EXEC Audit.ETL_Finish_Run
                @Run_UUID      = @My_Run_UUID,
                @Run_Status    = 'FAILED',
                @Rows_Inserted = @My_Inserts,
                @Rows_Updated  = @My_Updates,
                @Rows_Deleted  = @My_Deletes,
                @Error         = @My_Error;
        END
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
