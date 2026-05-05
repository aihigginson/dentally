--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Dim_Patients
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--    *03     01/05/2026  AIH Fix column names: Dentist_ID/Hygienist_ID -> Dentist_Practitioner_ID/Hygienist_Practitioner_ID
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Create_Dim_Patients @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Dim_Patients]
GO
CREATE PROCEDURE [Gold].[usp_Create_Dim_Patients]
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
    -- Local counters
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;    
    SET NOCOUNT ON;    
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

    DROP TABLE IF EXISTS Gold.Dim_Patients;

    CREATE TABLE Gold.Dim_Patients (
        pk_Patient                     BIGINT          NOT NULL,
        Tenant_ID                      INT             NOT NULL,
        Patient_ID                     INT             NOT NULL,
        Account_ID                     INT             NULL,
        Title                          VARCHAR(20)    NULL,
        First_Name                     VARCHAR(100)   NULL,
        Middle_Name                    VARCHAR(100)   NULL,
        Last_Name                      VARCHAR(100)   NULL,
        Preferred_Name                 VARCHAR(100)   NULL,
        Full_Name                      VARCHAR(255)   NULL,
        Date_Of_Birth                  DATE            NULL,
        Age_Years                      INT             NULL,
        Gender_Code                    INT             NULL,
        Gender_Description             VARCHAR(20)    NULL,
        Ethnicity_Code                 INT             NULL,
        NHS_Number                     VARCHAR(20)    NULL,
        NI_Number                      VARCHAR(20)    NULL,
        Email_Address                  VARCHAR(255)   NULL,
        Home_Phone                     VARCHAR(50)    NULL,
        Mobile_Phone                   VARCHAR(50)    NULL,
        Work_Phone                     VARCHAR(50)    NULL,
        Address_Line_1                 VARCHAR(255)   NULL,
        Address_Line_2                 VARCHAR(255)   NULL,
        Town                           VARCHAR(100)   NULL,
        County                         VARCHAR(100)   NULL,
        Postcode                       VARCHAR(20)    NULL,
        Active                         BIT             NULL,
        Medical_Alert                  BIT             NULL,
        Medical_Alert_Text             VARCHAR(255)   NULL,
        Payment_Plan_ID                INT             NULL,
        Site_ID                        VARCHAR(50)    NULL,
        Family_ID                      VARCHAR(255)   NULL,
        Acquisition_Source_ID          VARCHAR(50)    NULL,
        Dentist_Practitioner_ID        INT             NULL,
        Hygienist_Practitioner_ID      INT             NULL,
        Dentist_Recall_Date            DATE            NULL,
        Dentist_Recall_Interval_Months INT             NULL,
        Hygienist_Recall_Date          DATE            NULL,
        Hygienist_Recall_Interval_Months INT           NULL,
        Recall_Method                  VARCHAR(100)   NULL,
        Preferred_Contact_Method       VARCHAR(50)    NULL,
        Use_Email                      BIT             NULL,
        Use_SMS                        BIT             NULL,
        Marketing_Consent              VARCHAR(255)   NULL,
        Occupation                     VARCHAR(255)   NULL,
        Legacy_ID                      VARCHAR(255)   NULL,
        Custom_Field_1                 VARCHAR(255)   NULL,
        Custom_Field_2                 VARCHAR(255)   NULL,
        First_Appointment_Date         DATE            NULL,
        Last_Appointment_Date          DATE            NULL,
        Next_Appointment_Date          DATE            NULL,
        First_Exam_Date                DATE            NULL,
        Last_Exam_Date                 DATE            NULL,
        Next_Exam_Date                 DATE            NULL,
        Last_Scale_Polish_Date         DATE            NULL,
        Next_Scale_Polish_Date         DATE            NULL,
        Last_FTA_Date                  DATE            NULL,
        Last_Cancelled_Appointment_Date DATE           NULL,
        Total_Paid                     DECIMAL(18,4)   NULL,
        Total_Invoiced                 DECIMAL(18,4)   NULL,
        NHS_Exemption_Code             INT             NULL,
        Patient_Created_Date           DATE            NULL,
        Patient_Updated_Date           DATE            NULL,
        DW_Created_At                  datetime2(6)    NOT NULL,
        DW_Updated_At                  datetime2(6)    NOT NULL
    );

        -- Insert -1 unknown/shared seed row
        INSERT INTO Gold.Dim_Patients (pk_Patient, Tenant_ID, Patient_ID, DW_Created_At, DW_Updated_At)
        VALUES (-1, -1, -1, SYSUTCDATETIME(), SYSUTCDATETIME());

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************


    END TRY

    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Inserts

END

GO
