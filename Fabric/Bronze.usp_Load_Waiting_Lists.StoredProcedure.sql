--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_Waiting_Lists] @Tenant_ID=1, @Full_Refresh=1, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Waiting_Lists
--  Author           :  AIH
--  Initital Date    :  15/05/2026
--  History          :
--    *01     15/05/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Waiting_Lists @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Waiting_Lists]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Waiting_Lists]
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
    DECLARE @My_Inserts  BIGINT = 0;
    DECLARE @My_Updates  BIGINT = 0;
    DECLARE @My_Deletes  BIGINT = 0;
    DECLARE @My_Run_UUID VARCHAR(36);
    SET NOCOUNT ON;
    DECLARE @Proc_Options VARCHAR(1000);
    DECLARE @Parent_UUID  VARCHAR(36);
    SET @Proc_Options = CONCAT('@Tenant_ID = ', CAST(@Tenant_ID AS VARCHAR), ', @Full_Refresh = ', CAST(@Full_Refresh AS INT));
    SET @Parent_UUID  = ISNULL(CONVERT(VARCHAR(36), @Run_UUID), '00000000-0000-0000-0000-000000000000');
    IF @Logging = 1
        EXEC Audit.ETL_Start_Run
            @Run_Process_Name    = 'Bronze.usp_Load_Waiting_Lists',
            @Run_Process_Options = @Proc_Options,
            @Run_UUID            = @My_Run_UUID OUTPUT,
            @Parent_Run_UUID     = @Parent_UUID;

    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id AS INT)                                                AS Tenant_ID
            , LEFT(id, 255)                                                             AS ID
            , CASE WHEN active IN ('True', '1', 'true') THEN 1 ELSE 0 END              AS Active
            , LEFT(name, 255)                                                           AS Name
            , LEFT(site_id, 255)                                                        AS Site_ID
            , LEFT(default_appointment_reason, 255)                                     AS Default_Appointment_Reason
            , LEFT(default_treatment_reason,   255)                                     AS Default_Treatment_Reason
            , LEFT(default_notes,              255)                                     AS Default_Notes
            , LEFT(default_status,             255)                                     AS Default_Status
            , TRY_CAST(default_appointment_duration AS DECIMAL(18,4))                  AS Default_Appointment_Duration
            , TRY_CAST(default_treatment_duration   AS DECIMAL(18,4))                  AS Default_Treatment_Duration
            , TRY_CAST(target_appointment_days      AS DECIMAL(18,4))                  AS Target_Appointment_Days
            , TRY_CAST(target_treatment_days        AS DECIMAL(18,4))                  AS Target_Treatment_Days
        INTO #src
        FROM Stage.Waiting_Lists
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Active                       = src.Active
            , tgt.Name                         = src.Name
            , tgt.Site_ID                      = src.Site_ID
            , tgt.Default_Appointment_Reason   = src.Default_Appointment_Reason
            , tgt.Default_Treatment_Reason     = src.Default_Treatment_Reason
            , tgt.Default_Notes                = src.Default_Notes
            , tgt.Default_Status               = src.Default_Status
            , tgt.Default_Appointment_Duration = src.Default_Appointment_Duration
            , tgt.Default_Treatment_Duration   = src.Default_Treatment_Duration
            , tgt.Target_Appointment_Days      = src.Target_Appointment_Days
            , tgt.Target_Treatment_Days        = src.Target_Treatment_Days
            , tgt.DW_Loaded_At                 = SYSUTCDATETIME()
        FROM Bronze.Waiting_Lists AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Waiting_Lists (
            Tenant_ID, ID, Active, Name, Site_ID,
            Default_Appointment_Reason, Default_Treatment_Reason, Default_Notes, Default_Status,
            Default_Appointment_Duration, Default_Treatment_Duration,
            Target_Appointment_Days, Target_Treatment_Days,
            DW_Loaded_At
        )
        SELECT
            src.Tenant_ID, src.ID, src.Active, src.Name, src.Site_ID,
            src.Default_Appointment_Reason, src.Default_Treatment_Reason, src.Default_Notes, src.Default_Status,
            src.Default_Appointment_Duration, src.Default_Treatment_Duration,
            src.Target_Appointment_Days, src.Target_Treatment_Days,
            SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Waiting_Lists tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Waiting_Lists AS tgt
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
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
