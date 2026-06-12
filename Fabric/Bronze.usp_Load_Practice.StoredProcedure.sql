--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Practice
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *03     19/05/2026  AIH Fix phone_number to VARCHAR; add Town
--    *04     02/06/2026  AIH Boolean columns stored raw (VARCHAR) in Bronze; cast moved to Silver
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Practice]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Practice]
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
              TRY_CAST(tenant_id                      AS INT)         AS Tenant_ID
            , LEFT(id,                                   255)         AS Practice_ID
            , LEFT(name,                                 255)         AS Practice_Name
            , LEFT(email_address,                        255)         AS Email_Address
            , LEFT(phone_number, 255)                                 AS Phone_Number
            , LEFT(address_line_1,                       255)         AS Address_Line_1
            , LEFT(address_line_2,                       255)         AS Address_Line_2
            , LEFT(postcode,                             255)         AS Postcode
            , LEFT(town,                                 255)         AS Town
            , LEFT(website,                              255)         AS Website
            , LEFT(logo_url,                             255)         AS Logo_Url
            , LEFT(slug,                                 255)         AS Slug
            , LEFT(time_zone,                            255)         AS Time_Zone
            , LEFT(patient_email_address,                255)         AS Patient_Email_Address
            , LEFT(custom_patient_field_label_1,         255)         AS Custom_Patient_Field_Label_1
            , LEFT(custom_patient_field_label_2,         255)         AS Custom_Patient_Field_Label_2
            , TRY_CAST(medical_history_expiry_days AS DECIMAL(18,4))  AS Medical_History_Expiry_Days
            , LEFT(nhs,                255)  AS NHS
            , LEFT(oh_mon_open,                          255)         AS [Oh_Mon#open]
            , LEFT(oh_mon_close,                         255)         AS [Oh_Mon#close]
            , LEFT(oh_tues_open,                         255)         AS [Oh_Tues#open]
            , LEFT(oh_tues_close,                        255)         AS [Oh_Tues#close]
            , LEFT(oh_wed_open,                          255)         AS [Oh_Wed#open]
            , LEFT(oh_wed_close,                         255)         AS [Oh_Wed#close]
            , LEFT(oh_thur_open,                         255)         AS [Oh_Thur#open]
            , LEFT(oh_thur_close,                        255)         AS [Oh_Thur#close]
            , LEFT(oh_fri_open,                          255)         AS [Oh_Fri#open]
            , LEFT(oh_fri_close,                         255)         AS [Oh_Fri#close]
            , LEFT(oh_sat_open,                          255)         AS [Oh_Sat#open]
            , LEFT(oh_sat_close,                         255)         AS [Oh_Sat#close]
            , LEFT(oh_sun_open,                          255)         AS [Oh_Sun#open]
            , LEFT(oh_sun_close,                         255)         AS [Oh_Sun#close]
        INTO #src
        FROM Stage.Practice
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Practice_Name                = src.Practice_Name
            , tgt.Email_Address                = src.Email_Address
            , tgt.Phone_Number                 = src.Phone_Number
            , tgt.Address_Line_1               = src.Address_Line_1
            , tgt.Address_Line_2               = src.Address_Line_2
            , tgt.Postcode                     = src.Postcode
            , tgt.Town                         = src.Town
            , tgt.Website                      = src.Website
            , tgt.Logo_Url                     = src.Logo_Url
            , tgt.Slug                         = src.Slug
            , tgt.Time_Zone                    = src.Time_Zone
            , tgt.Patient_Email_Address        = src.Patient_Email_Address
            , tgt.Custom_Patient_Field_Label_1 = src.Custom_Patient_Field_Label_1
            , tgt.Custom_Patient_Field_Label_2 = src.Custom_Patient_Field_Label_2
            , tgt.Medical_History_Expiry_Days  = src.Medical_History_Expiry_Days
            , tgt.NHS                          = src.NHS
            , tgt.[Oh_Mon#open]                = src.[Oh_Mon#open]
            , tgt.[Oh_Mon#close]               = src.[Oh_Mon#close]
            , tgt.[Oh_Tues#open]               = src.[Oh_Tues#open]
            , tgt.[Oh_Tues#close]              = src.[Oh_Tues#close]
            , tgt.[Oh_Wed#open]                = src.[Oh_Wed#open]
            , tgt.[Oh_Wed#close]               = src.[Oh_Wed#close]
            , tgt.[Oh_Thur#open]               = src.[Oh_Thur#open]
            , tgt.[Oh_Thur#close]              = src.[Oh_Thur#close]
            , tgt.[Oh_Fri#open]                = src.[Oh_Fri#open]
            , tgt.[Oh_Fri#close]               = src.[Oh_Fri#close]
            , tgt.[Oh_Sat#open]                = src.[Oh_Sat#open]
            , tgt.[Oh_Sat#close]               = src.[Oh_Sat#close]
            , tgt.[Oh_Sun#open]                = src.[Oh_Sun#open]
            , tgt.[Oh_Sun#close]               = src.[Oh_Sun#close]
            , tgt.DW_Loaded_At                 = SYSUTCDATETIME()
        FROM Bronze.Practice AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Practice_ID = src.Practice_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Practice (Tenant_ID, Practice_ID, Practice_Name, Email_Address, Phone_Number, Address_Line_1, Address_Line_2, Postcode, Town, Website, Logo_Url, Slug, Time_Zone, Patient_Email_Address, Custom_Patient_Field_Label_1, Custom_Patient_Field_Label_2, Medical_History_Expiry_Days, NHS, [Oh_Mon#open], [Oh_Mon#close], [Oh_Tues#open], [Oh_Tues#close], [Oh_Wed#open], [Oh_Wed#close], [Oh_Thur#open], [Oh_Thur#close], [Oh_Fri#open], [Oh_Fri#close], [Oh_Sat#open], [Oh_Sat#close], [Oh_Sun#open], [Oh_Sun#close], DW_Loaded_At)
        SELECT src.Tenant_ID, src.Practice_ID, src.Practice_Name, src.Email_Address, src.Phone_Number, src.Address_Line_1, src.Address_Line_2, src.Postcode, src.Town, src.Website, src.Logo_Url, src.Slug, src.Time_Zone, src.Patient_Email_Address, src.Custom_Patient_Field_Label_1, src.Custom_Patient_Field_Label_2, src.Medical_History_Expiry_Days, src.NHS, src.[Oh_Mon#open], src.[Oh_Mon#close], src.[Oh_Tues#open], src.[Oh_Tues#close], src.[Oh_Wed#open], src.[Oh_Wed#close], src.[Oh_Thur#open], src.[Oh_Thur#close], src.[Oh_Fri#open], src.[Oh_Fri#close], src.[Oh_Sat#open], src.[Oh_Sat#close], src.[Oh_Sun#open], src.[Oh_Sun#close], SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Practice tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Practice_ID = src.Practice_ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Practice AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE Practice_ID = tgt.Practice_ID);
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
