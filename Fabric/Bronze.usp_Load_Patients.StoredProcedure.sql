--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Patients
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Patients @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Patients]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Patients]
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
            @Run_Process_Name    = 'Bronze.usp_Load_Patients',
            @Run_Process_Options = @Proc_Options,
            @Run_UUID            = @My_Run_UUID OUTPUT,
            @Parent_Run_UUID     = @Parent_UUID;

    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id               AS INT)            AS Tenant_ID
            , TRY_CAST(id                      AS INT)            AS Patient_ID
            , TRY_CAST(account_id              AS INT)            AS Account_ID
            , CASE WHEN active = 'True' THEN 1 ELSE 0 END         AS Active
            , LEFT(first_name,                    255)            AS First_Name
            , LEFT(last_name,                     255)            AS Last_Name
            , LEFT(date_of_birth,                 255)            AS Date_Of_Birth
            , CASE WHEN gender = 'False' THEN 0 ELSE 1 END        AS Gender
            , LEFT(email_address,                 255)            AS Email_Address
            , LEFT(mobile_phone,                  255)            AS Mobile_Phone
            , LEFT(home_phone,                    255)            AS Home_Phone
            , LEFT(address_line_1,                255)            AS Address_Line_1
            , LEFT(address_line_2,                255)            AS Address_Line_2
            , LEFT(town,                          255)            AS Town
            , LEFT(county,                        255)            AS County
            , LEFT(postcode,                      255)            AS Postcode
            , TRY_CAST(payment_plan_id           AS INT)          AS Payment_Plan_ID
            , TRY_CAST(dentist_id                AS INT)          AS Dentist_ID
            , TRY_CAST(hygienist_id              AS INT)          AS Hygienist_ID
            , LEFT(site_id,                       255)            AS Site_ID
            , TRY_CAST(dentist_recall_interval   AS DECIMAL(18,4)) AS Dentist_Recall_Interval
            , TRY_CAST(hygienist_recall_interval AS DECIMAL(18,4)) AS Hygienist_Recall_Interval
            , LEFT(dentist_recall_date,           255)            AS Dentist_Recall_Date
            , LEFT(hygienist_recall_date,         255)            AS Hygienist_Recall_Date
            , LEFT(nhs_number,                    255)            AS NHS_Number
            , LEFT(ni_number,                     255)            AS Ni_Number
            , LEFT(marketing,                     255)            AS Marketing
            , CASE WHEN medical_alert = 'False' THEN 0 ELSE 1 END AS Medical_Alert
            , LEFT(medical_alert_text,            255)            AS Medical_Alert_Text
            , LEFT(occupation,                    255)            AS Occupation
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
            , tgt.Date_Of_Birth            = src.Date_Of_Birth
            , tgt.Gender                   = src.Gender
            , tgt.Email_Address            = src.Email_Address
            , tgt.Mobile_Phone             = src.Mobile_Phone
            , tgt.Home_Phone               = src.Home_Phone
            , tgt.Address_Line_1           = src.Address_Line_1
            , tgt.Address_Line_2           = src.Address_Line_2
            , tgt.Town                     = src.Town
            , tgt.County                   = src.County
            , tgt.Postcode                 = src.Postcode
            , tgt.Payment_Plan_ID          = src.Payment_Plan_ID
            , tgt.Dentist_ID               = src.Dentist_ID
            , tgt.Hygienist_ID             = src.Hygienist_ID
            , tgt.Site_ID                  = src.Site_ID
            , tgt.Dentist_Recall_Interval  = src.Dentist_Recall_Interval
            , tgt.Hygienist_Recall_Interval = src.Hygienist_Recall_Interval
            , tgt.Dentist_Recall_Date      = src.Dentist_Recall_Date
            , tgt.Hygienist_Recall_Date    = src.Hygienist_Recall_Date
            , tgt.NHS_Number               = src.NHS_Number
            , tgt.Ni_Number                = src.Ni_Number
            , tgt.Marketing                = src.Marketing
            , tgt.Medical_Alert            = src.Medical_Alert
            , tgt.Medical_Alert_Text       = src.Medical_Alert_Text
            , tgt.Occupation               = src.Occupation
            , tgt.Created_At               = src.Created_At
            , tgt.Updated_At               = src.Updated_At
            , tgt.DW_Loaded_At             = SYSUTCDATETIME()
        FROM Bronze.Patients AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Patient_ID = src.Patient_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Patients (
            Tenant_ID,
            Patient_ID,
            Account_ID ,
            Active,
            First_Name,
            Last_Name,
            Date_Of_Birth,
            Gender, 
            Email_Address,
            Mobile_Phone,
            Home_Phone,
            Address_Line_1,
            Address_Line_2,
            Town,
            County,
            Postcode,
            Payment_Plan_ID,
            Dentist_ID,
            Hygienist_ID,
            Site_ID ,
            Dentist_Recall_Interval,
            Hygienist_Recall_Interval,
            Dentist_Recall_Date,
            Hygienist_Recall_Date,
            NHS_Number,
            Ni_Number,
            Marketing,
            Medical_Alert,
            Medical_Alert_Text,
            Occupation,
            Created_At,
            Updated_At,
            DW_Loaded_At 
        )
        SELECT
            src.Tenant_ID,
            src.Patient_ID,
            src.Account_ID ,
            src.Active,
            src.First_Name,
            src.Last_Name,
            src.Date_Of_Birth,
            src.Gender,
            src.Email_Address,
            src.Mobile_Phone,
            src.Home_Phone,
            src.Address_Line_1,
            src.Address_Line_2,
            src.Town,
            src.County,
            src.Postcode,
            src.Payment_Plan_ID,
            src.Dentist_ID,
            src.Hygienist_ID,
            src.Site_ID  ,
            src.Dentist_Recall_Interval,
            src.Hygienist_Recall_Interval,
            src.Dentist_Recall_Date,
            src.Hygienist_Recall_Date,
            src.NHS_Number,
            src.Ni_Number,
            src.Marketing,
            src.Medical_Alert,
            src.Medical_Alert_Text,
            src.Occupation,
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


