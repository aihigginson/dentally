--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Recalls
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     13/05/2026  AIH Add First_Reminder_Sent_At from Stage
--    *03     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Recalls @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Recalls]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Recalls]
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
            @Run_Process_Name    = 'Bronze.usp_Load_Recalls',
            @Run_Process_Options = @Proc_Options,
            @Run_UUID            = @My_Run_UUID OUTPUT,
            @Parent_Run_UUID     = @Parent_UUID;

    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id      AS INT)            AS Tenant_ID
            , LEFT(id,                  255)             AS ID
            , TRY_CAST(patient_id     AS DECIMAL(18,4))  AS Patient_ID
            , LEFT(recall_type,         255)             AS Recall_Type
            , LEFT(due_date,            255)             AS Due_Date
            , TRY_CAST(times_contacted AS DECIMAL(18,4)) AS Times_Contacted
            , LEFT(status,              255)             AS Status
            , LEFT(first_reminder_sent_at, 255)          AS First_Reminder_Sent_At
        INTO #src
        FROM Stage.Recalls
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Patient_ID               = src.Patient_ID
            , tgt.Recall_Type              = src.Recall_Type
            , tgt.Due_Date                 = src.Due_Date
            , tgt.Times_Contacted          = src.Times_Contacted
            , tgt.Status                   = src.Status
            , tgt.First_Reminder_Sent_At   = src.First_Reminder_Sent_At
            , tgt.DW_Loaded_At             = SYSUTCDATETIME()
        FROM Bronze.Recalls AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Recalls (Tenant_ID, ID, Patient_ID, Recall_Type, Due_Date, Times_Contacted, Status, First_Reminder_Sent_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Patient_ID, src.Recall_Type, src.Due_Date, src.Times_Contacted, src.Status, src.First_Reminder_Sent_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Recalls tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Recalls AS tgt
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
