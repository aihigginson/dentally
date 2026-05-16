--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Patient_Stats
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Patient_Stats]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Patient_Stats]
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
    SET NOCOUNT ON;
    DECLARE @Proc_Options VARCHAR(1000);
    DECLARE @Parent_UUID  VARCHAR(36);
    SET @Proc_Options = CONCAT('@Tenant_ID = ', CAST(@Tenant_ID AS VARCHAR), ', @Full_Refresh = ', CAST(@Full_Refresh AS INT));
    SET @Parent_UUID  = ISNULL(CONVERT(VARCHAR(36), @Run_UUID), '00000000-0000-0000-0000-000000000000');
    IF @Logging = 1
        EXEC Audit.ETL_Start_Run
            @Run_Process_Name    = 'Bronze.usp_Load_Patient_Stats',
            @Run_Process_Options = @Proc_Options,
            @Run_UUID            = @My_Run_UUID OUTPUT,
            @Parent_Run_UUID     = @Parent_UUID;

    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id AS INT)                                   AS Tenant_ID
            , TRY_CAST(patient_id AS DECIMAL(18,4))                        AS Patient_ID
            , LEFT(last_appointment_date, 255)                             AS Last_Appointment_Date
            , LEFT(last_exam_date, 255)                                    AS Last_Exam_Date
            , LEFT(last_scale_and_polish_date, 255)                        AS Last_Scale_And_Polish_Date
            , LEFT(next_appointment_date, 255)                             AS Next_Appointment_Date
            , LEFT(next_exam_date, 255)                                    AS Next_Exam_Date
            , LEFT(next_scale_and_polish_date, 255)                        AS Next_Scale_And_Polish_Date
            , LEFT(created_at, 255)                                        AS Created_At
            , LEFT(updated_at, 255)                                        AS Updated_At
            , TRY_CAST(total_paid AS DECIMAL(18,4))                        AS Total_Paid
            , TRY_CAST(total_invoiced AS DECIMAL(18,4))                    AS Total_Invoiced
            , LEFT(last_fta_appointment_date, 255)                         AS Last_Fta_Appointment_Date
            , LEFT(first_appointment_date, 255)                            AS First_Appointment_Date
            , LEFT(first_exam_date, 255)                                   AS First_Exam_Date
            , TRY_CAST(nhs_exemption_code AS DECIMAL(18,4))                AS NHS_Exemption_Code
            , LEFT(last_cancelled_appointment_date, 255)                   AS Last_Cancelled_Appointment_Date
        INTO #src
        FROM Stage.Patient_Stats
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Last_Appointment_Date          = src.Last_Appointment_Date
            , tgt.Last_Exam_Date                 = src.Last_Exam_Date
            , tgt.Last_Scale_And_Polish_Date      = src.Last_Scale_And_Polish_Date
            , tgt.Next_Appointment_Date           = src.Next_Appointment_Date
            , tgt.Next_Exam_Date                  = src.Next_Exam_Date
            , tgt.Next_Scale_And_Polish_Date      = src.Next_Scale_And_Polish_Date
            , tgt.Updated_At                      = src.Updated_At
            , tgt.Total_Paid                      = src.Total_Paid
            , tgt.Total_Invoiced                  = src.Total_Invoiced
            , tgt.Last_Fta_Appointment_Date       = src.Last_Fta_Appointment_Date
            , tgt.First_Appointment_Date          = src.First_Appointment_Date
            , tgt.First_Exam_Date                 = src.First_Exam_Date
            , tgt.NHS_Exemption_Code              = src.NHS_Exemption_Code
            , tgt.Last_Cancelled_Appointment_Date = src.Last_Cancelled_Appointment_Date
            , tgt.DW_Loaded_At                    = SYSUTCDATETIME()
        FROM Bronze.Patient_Stats AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Patient_ID = src.Patient_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Patient_Stats (Tenant_ID, Patient_ID, Last_Appointment_Date, Last_Exam_Date, Last_Scale_And_Polish_Date, Next_Appointment_Date, Next_Exam_Date, Next_Scale_And_Polish_Date, Created_At, Updated_At, Total_Paid, Total_Invoiced, Last_Fta_Appointment_Date, First_Appointment_Date, First_Exam_Date, NHS_Exemption_Code, Last_Cancelled_Appointment_Date, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Patient_ID, src.Last_Appointment_Date, src.Last_Exam_Date, src.Last_Scale_And_Polish_Date, src.Next_Appointment_Date, src.Next_Exam_Date, src.Next_Scale_And_Polish_Date, src.Created_At, src.Updated_At, src.Total_Paid, src.Total_Invoiced, src.Last_Fta_Appointment_Date, src.First_Appointment_Date, src.First_Exam_Date, src.NHS_Exemption_Code, src.Last_Cancelled_Appointment_Date, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Patient_Stats tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Patient_ID = src.Patient_ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Patient_Stats AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE Patient_ID = tgt.Patient_ID);
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
