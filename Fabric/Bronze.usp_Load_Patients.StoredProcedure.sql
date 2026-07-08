--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Patients
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *03     19/05/2026  AIH Add 15 new patient fields (title, recall_method, acquisition_source_id, use_email/sms, preferred_name, work_phone, middle_name, emergency_contact_*, ethnicity, archived_reason, legacy_id, preferred_phone_number)
--    *04     20/05/2026  AIH Fix Stage field name: ethnicity -> ethnicity_id; Preferred_Phone_Number VARCHAR not decimal
--    *05     02/06/2026  AIH Boolean columns stored raw (VARCHAR) in Bronze; cast moved to Silver
--    *06     17/06/2026  AIH DATA MINIMISATION (V011): stop landing special-category + excess-identifier fields;
--                            load identity-for-contact, marketing flag + operational analytics only
--    *07     19/06/2026  AIH V015: re-land contact-preference fields (use_email, use_sms, preferred_phone)
--    *08     07/07/2026  AIH Read real field preferred_phone_number (Dentally code 1=Home/2=Work/3=Mobile),
--                            not the mock's preferred_phone. Silver resolves the code to the actual number.
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Patients @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Patients]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Patients]
(
      @Tenant_ID    INT
    , @Full_Refresh BIT              = 0
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
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id               AS INT)            AS Tenant_ID
            , TRY_CAST(id                      AS INT)            AS Patient_ID
            , TRY_CAST(account_id              AS INT)            AS Account_ID
            , LEFT(active,                             255)         AS Active
            , LEFT(first_name,                    255)            AS First_Name
            , LEFT(last_name,                     255)            AS Last_Name
            , LEFT(email_address,                 255)            AS Email_Address
            , LEFT(mobile_phone,                  255)            AS Mobile_Phone
            , LEFT(home_phone,                    255)            AS Home_Phone
            , LEFT(use_email,                     255)            AS Use_Email
            , LEFT(use_sms,                       255)            AS Use_SMS
            , LEFT(preferred_phone_number,        255)            AS Preferred_Phone
            , TRY_CAST(payment_plan_id           AS INT)          AS Payment_Plan_ID
            , TRY_CAST(dentist_id                AS INT)          AS Dentist_ID
            , TRY_CAST(hygienist_id              AS INT)          AS Hygienist_ID
            , LEFT(site_id,                       255)            AS Site_ID
            , TRY_CAST(dentist_recall_interval   AS DECIMAL(18,4)) AS Dentist_Recall_Interval
            , TRY_CAST(hygienist_recall_interval AS DECIMAL(18,4)) AS Hygienist_Recall_Interval
            , LEFT(dentist_recall_date,           255)            AS Dentist_Recall_Date
            , LEFT(hygienist_recall_date,         255)            AS Hygienist_Recall_Date
            , LEFT(marketing,                     255)            AS Marketing
            , LEFT(recall_method,                  255)            AS Recall_Method
            , LEFT(acquisition_source_id,          255)            AS Acquisition_Source_ID
            , LEFT(preferred_name,                 255)            AS Preferred_Name
            , LEFT(created_at,                    255)            AS Created_At
            , LEFT(updated_at,                    255)            AS Updated_At
        INTO #src
        FROM Stage.Patients
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Account_ID               = src.Account_ID
            , tgt.Active                   = src.Active
            , tgt.First_Name               = src.First_Name
            , tgt.Last_Name                = src.Last_Name
            , tgt.Email_Address            = src.Email_Address
            , tgt.Mobile_Phone             = src.Mobile_Phone
            , tgt.Home_Phone               = src.Home_Phone
            , tgt.Use_Email                = src.Use_Email
            , tgt.Use_SMS                  = src.Use_SMS
            , tgt.Preferred_Phone          = src.Preferred_Phone
            , tgt.Payment_Plan_ID          = src.Payment_Plan_ID
            , tgt.Dentist_ID               = src.Dentist_ID
            , tgt.Hygienist_ID             = src.Hygienist_ID
            , tgt.Site_ID                  = src.Site_ID
            , tgt.Dentist_Recall_Interval  = src.Dentist_Recall_Interval
            , tgt.Hygienist_Recall_Interval = src.Hygienist_Recall_Interval
            , tgt.Dentist_Recall_Date      = src.Dentist_Recall_Date
            , tgt.Hygienist_Recall_Date    = src.Hygienist_Recall_Date
            , tgt.Marketing                = src.Marketing
            , tgt.Recall_Method            = src.Recall_Method
            , tgt.Acquisition_Source_ID    = src.Acquisition_Source_ID
            , tgt.Preferred_Name           = src.Preferred_Name
            , tgt.Created_At               = src.Created_At
            , tgt.Updated_At               = src.Updated_At
            , tgt.DW_Loaded_At             = SYSUTCDATETIME()
        FROM Bronze.Patients AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Patient_ID = src.Patient_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Patients (
            Tenant_ID,
            Patient_ID,
            Account_ID,
            Active,
            First_Name,
            Last_Name,
            Email_Address,
            Mobile_Phone,
            Home_Phone,
            Use_Email,
            Use_SMS,
            Preferred_Phone,
            Payment_Plan_ID,
            Dentist_ID,
            Hygienist_ID,
            Site_ID,
            Dentist_Recall_Interval,
            Hygienist_Recall_Interval,
            Dentist_Recall_Date,
            Hygienist_Recall_Date,
            Marketing,
            Recall_Method,
            Acquisition_Source_ID,
            Preferred_Name,
            Created_At,
            Updated_At,
            DW_Loaded_At
        )
        SELECT
            src.Tenant_ID,
            src.Patient_ID,
            src.Account_ID,
            src.Active,
            src.First_Name,
            src.Last_Name,
            src.Email_Address,
            src.Mobile_Phone,
            src.Home_Phone,
            src.Use_Email,
            src.Use_SMS,
            src.Preferred_Phone,
            src.Payment_Plan_ID,
            src.Dentist_ID,
            src.Hygienist_ID,
            src.Site_ID,
            src.Dentist_Recall_Interval,
            src.Hygienist_Recall_Interval,
            src.Dentist_Recall_Date,
            src.Hygienist_Recall_Date,
            src.Marketing,
            src.Recall_Method,
            src.Acquisition_Source_ID,
            src.Preferred_Name,
            src.Created_At,
            src.Updated_At,
            SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Patients tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Patient_ID = src.Patient_ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Patients AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE Patient_ID = tgt.Patient_ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
