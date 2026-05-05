--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Patients
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Add -1 unknown seed row; protect from DELETE
--    *03     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Patients @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Patients]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Patients]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Patients]
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
            p.Tenant_ID AS Tenant_ID,
            CAST(p.Patient_Id AS INT)                                                               AS Patient_ID,
            CAST(p.Account_Id AS INT)                                                               AS Account_ID,
            NULLIF(TRIM(p.Title), '')                                                               AS Title,
            NULLIF(TRIM(p.First_Name), '')                                                          AS First_Name,
            NULLIF(TRIM(p.Middle_Name), '')                                                         AS Middle_Name,
            NULLIF(TRIM(p.Last_Name), '')                                                           AS Last_Name,
            NULLIF(TRIM(p.Preferred_Name), '')                                                      AS Preferred_Name,
            NULLIF(CONCAT_WS(' ',
                NULLIF(TRIM(p.Title), ''),
                NULLIF(TRIM(p.First_Name), ''),
                NULLIF(TRIM(p.Last_Name), '')), '')                                                 AS Full_Name,
            CAST(p.Date_Of_Birth AS DATE)                                                           AS Date_Of_Birth,
            CASE WHEN p.Date_Of_Birth IS NOT NULL
                      THEN DATEDIFF(YEAR, p.Date_Of_Birth, SYSUTCDATETIME())
                          - CASE WHEN MONTH(SYSUTCDATETIME()) < MONTH(p.Date_Of_Birth)
                                      OR (MONTH(SYSUTCDATETIME()) = MONTH(p.Date_Of_Birth)
                                          AND DAY(SYSUTCDATETIME()) < DAY(p.Date_Of_Birth))
                                THEN 1 ELSE 0 END
                 END                                                                                AS Age_Years,
            p.Gender                                                                                AS Gender_Description,
            p.Ethnicity                                                                             AS Ethnicity_Code,
            NULLIF(TRIM(p.NHS_Number), '')                                                          AS NHS_Number,
            NULLIF(TRIM(p.NI_Number), '')                                                           AS NI_Number,
            NULLIF(TRIM(p.Email_Address), '')                                                       AS Email_Address,
            NULLIF(TRIM(p.Home_Phone), '')                                                          AS Home_Phone,
            NULLIF(TRIM(p.Mobile_Phone), '')                                                        AS Mobile_Phone,
            NULLIF(TRIM(p.Work_Phone), '')                                                          AS Work_Phone,
            NULLIF(TRIM(p.Address_Line_1), '')                                                      AS Address_Line_1,
            NULLIF(TRIM(p.Address_Line_2), '')                                                      AS Address_Line_2,
            NULLIF(TRIM(p.Town), '')                                                                AS Town,
            NULLIF(TRIM(p.County), '')                                                              AS County,
            NULLIF(TRIM(p.Postcode), '')                                                            AS Postcode,
            CAST(ISNULL(p.Active, 0) AS BIT)                                                        AS Active,
            CAST(ISNULL(p.Medical_Alert, 0) AS BIT)                                                 AS Medical_Alert,
            NULLIF(TRIM(p.Medical_Alert_Text), '')                                                  AS Medical_Alert_Text,
            CAST(p.Payment_Plan_Id AS INT)                                                          AS Payment_Plan_ID,
            NULLIF(TRIM(p.Site_Id), '')                                                             AS Site_ID,
            NULLIF(TRIM(p.Family_Id), '')                                                           AS Family_ID,
            NULLIF(TRIM(p.Acquisition_Source_Id), '')                                               AS Acquisition_Source_ID,
            CAST(p.Dentist_Practitioner_Id AS INT)                                                  AS Dentist_Practitioner_ID,
            CAST(p.Hygienist_Practitioner_Id AS INT)                                                AS Hygienist_Practitioner_ID,
            CAST(p.Dentist_Recall_Date AS DATE)                                                     AS Dentist_Recall_Date,
            CAST(p.Dentist_Recall_Interval AS INT)                                                  AS Dentist_Recall_Interval_Months,
            CAST(p.Hygienist_Recall_Date AS DATE)                                                   AS Hygienist_Recall_Date,
            CAST(p.Hygienist_Recall_Interval AS INT)                                                AS Hygienist_Recall_Interval_Months,
            NULLIF(TRIM(p.Recall_Method), '')                                                       AS Recall_Method,
            NULLIF(p.Marketing_Opt_In, 0)                                                           AS Marketing_Consent,
            NULLIF(TRIM(p.Custom_Field_1), '')                                                      AS Custom_Field_1,
            NULLIF(TRIM(p.Custom_Field_2), '')                                                      AS Custom_Field_2,
            TRY_CAST(NULLIF(TRIM(ps.First_Appointment_Date), '') AS DATE)                           AS First_Appointment_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date), '') AS DATE)                            AS Last_Appointment_Date,
            TRY_CAST(NULLIF(TRIM(ps.Next_Appointment_Date), '') AS DATE)                            AS Next_Appointment_Date,
            TRY_CAST(NULLIF(TRIM(ps.First_Exam_Date), '') AS DATE)                                  AS First_Exam_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Exam_Date), '') AS DATE)                                   AS Last_Exam_Date,
            TRY_CAST(NULLIF(TRIM(ps.Next_Exam_Date), '') AS DATE)                                   AS Next_Exam_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Scale_And_Polish_Date), '') AS DATE)                       AS Last_Scale_Polish_Date,
            TRY_CAST(NULLIF(TRIM(ps.Next_Scale_And_Polish_Date), '') AS DATE)                       AS Next_Scale_Polish_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Fta_Appointment_Date), '') AS DATE)                        AS Last_FTA_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Cancelled_Appointment_Date), '') AS DATE)                  AS Last_Cancelled_Appointment_Date,
            CAST(ps.Total_Paid AS DECIMAL(12,2))                                                    AS Total_Paid,
            CAST(ps.Total_Invoiced AS DECIMAL(12,2))                                                AS Total_Invoiced,
            TRY_CAST(ps.Nhs_Exemption_Code AS INT)                                                  AS NHS_Exemption_Code,
            TRY_CAST(p.Created_At AS DATE)                                                          AS Patient_Created_Date,
            TRY_CAST(p.Updated_At AS DATE)                                                          AS Patient_Updated_Date
        INTO #src
        FROM Silver.Patients p
        LEFT JOIN Silver.Patient_Stats ps ON ps.Patient_Id = p.Patient_Id AND ps.Tenant_ID = p.Tenant_ID
        WHERE p.Patient_Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Patients tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Patient_ID = tgt.Patient_ID AND Tenant_ID = tgt.Tenant_ID)
        AND tgt.pk_Patient <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Account_ID                          = src.Account_ID,
            Title                               = src.Title,
            First_Name                          = src.First_Name,
            Middle_Name                         = src.Middle_Name,
            Last_Name                           = src.Last_Name,
            Preferred_Name                      = src.Preferred_Name,
            Full_Name                           = src.Full_Name,
            Date_Of_Birth                       = src.Date_Of_Birth,
            Age_Years                           = src.Age_Years,
            Gender_Description                  = src.Gender_Description,
            Ethnicity_Code                      = src.Ethnicity_Code,
            NHS_Number                          = src.NHS_Number,
            NI_Number                           = src.NI_Number,
            Email_Address                       = src.Email_Address,
            Home_Phone                          = src.Home_Phone,
            Mobile_Phone                        = src.Mobile_Phone,
            Work_Phone                          = src.Work_Phone,
            Address_Line_1                      = src.Address_Line_1,
            Address_Line_2                      = src.Address_Line_2,
            Town                                = src.Town,
            County                              = src.County,
            Postcode                            = src.Postcode,
            Active                              = src.Active,
            Medical_Alert                       = src.Medical_Alert,
            Medical_Alert_Text                  = src.Medical_Alert_Text,
            Payment_Plan_ID                     = src.Payment_Plan_ID,
            Site_ID                             = src.Site_ID,
            Dentist_Recall_Date                 = src.Dentist_Recall_Date,
            Dentist_Recall_Interval_Months      = src.Dentist_Recall_Interval_Months,
            Hygienist_Recall_Date               = src.Hygienist_Recall_Date,
            Hygienist_Recall_Interval_Months    = src.Hygienist_Recall_Interval_Months,
            Recall_Method                       = src.Recall_Method,
            Marketing_Consent                   = src.Marketing_Consent,
            First_Appointment_Date              = src.First_Appointment_Date,
            Last_Appointment_Date               = src.Last_Appointment_Date,
            Next_Appointment_Date               = src.Next_Appointment_Date,
            First_Exam_Date                     = src.First_Exam_Date,
            Last_Exam_Date                      = src.Last_Exam_Date,
            Next_Exam_Date                      = src.Next_Exam_Date,
            Last_Scale_Polish_Date              = src.Last_Scale_Polish_Date,
            Next_Scale_Polish_Date              = src.Next_Scale_Polish_Date,
            Last_FTA_Date                       = src.Last_FTA_Date,
            Last_Cancelled_Appointment_Date     = src.Last_Cancelled_Appointment_Date,
            Total_Paid                          = src.Total_Paid,
            Total_Invoiced                      = src.Total_Invoiced,
            NHS_Exemption_Code                  = src.NHS_Exemption_Code,
            Patient_Updated_Date                = src.Patient_Updated_Date,
            DW_Updated_At                       = SYSUTCDATETIME()
        FROM Gold.Dim_Patients tgt
        INNER JOIN #src src ON tgt.Patient_ID = src.Patient_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Account_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Title] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Middle_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Preferred_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Date_Of_Birth] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Age_Years] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Gender_Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Ethnicity_Code] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NI_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Email_Address] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Home_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Work_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Address_Line_1] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Address_Line_2] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Town] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[County] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Postcode] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Medical_Alert] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Medical_Alert_Text] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Payment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Hygienist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Hygienist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Recall_Method] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Marketing_Consent] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Next_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Next_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Next_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_FTA_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Cancelled_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Total_Paid] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Total_Invoiced] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Exemption_Code] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Updated_Date] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Account_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Title] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Middle_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Preferred_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Date_Of_Birth] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Age_Years] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Gender_Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Ethnicity_Code] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NI_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Email_Address] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Home_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Work_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Address_Line_1] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Address_Line_2] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Town] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[County] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Postcode] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Medical_Alert] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Medical_Alert_Text] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Payment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Dentist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Dentist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Hygienist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Hygienist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Recall_Method] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Marketing_Consent] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Next_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Next_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Next_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_FTA_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Cancelled_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Total_Paid] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Total_Invoiced] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Exemption_Code] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Updated_Date] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_Patient_base BIGINT = ISNULL((SELECT MAX(pk_Patient) FROM Gold.Dim_Patients WHERE pk_Patient > 0), 0);
        INSERT INTO Gold.Dim_Patients (
            pk_Patient,
            Tenant_ID, Patient_ID, Account_ID, Title, First_Name, Middle_Name, Last_Name, Preferred_Name, Full_Name,
            Date_Of_Birth, Age_Years, Gender_Description, Ethnicity_Code,
            NHS_Number, NI_Number, Email_Address, Home_Phone, Mobile_Phone, Work_Phone,
            Address_Line_1, Address_Line_2, Town, County, Postcode,
            Active, Medical_Alert, Medical_Alert_Text, Payment_Plan_ID, Site_ID, Family_ID,
            Acquisition_Source_ID, Dentist_Practitioner_ID, Hygienist_Practitioner_ID,
            Dentist_Recall_Date, Dentist_Recall_Interval_Months,
            Hygienist_Recall_Date, Hygienist_Recall_Interval_Months,
            Recall_Method, Marketing_Consent, Custom_Field_1, Custom_Field_2,
            First_Appointment_Date, Last_Appointment_Date, Next_Appointment_Date,
            First_Exam_Date, Last_Exam_Date, Next_Exam_Date,
            Last_Scale_Polish_Date, Next_Scale_Polish_Date,
            Last_FTA_Date, Last_Cancelled_Appointment_Date,
            Total_Paid, Total_Invoiced, NHS_Exemption_Code,
            Patient_Created_Date, Patient_Updated_Date, DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_Patient_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Patient_ID),
            src.Tenant_ID, src.Patient_ID, src.Account_ID, src.Title, src.First_Name, src.Middle_Name, src.Last_Name,
            src.Preferred_Name, src.Full_Name, src.Date_Of_Birth, src.Age_Years,
            src.Gender_Description, src.Ethnicity_Code, src.NHS_Number, src.NI_Number, src.Email_Address,
            src.Home_Phone, src.Mobile_Phone, src.Work_Phone,
            src.Address_Line_1, src.Address_Line_2, src.Town, src.County, src.Postcode,
            src.Active, src.Medical_Alert, src.Medical_Alert_Text, src.Payment_Plan_ID, src.Site_ID, src.Family_ID,
            src.Acquisition_Source_ID, src.Dentist_Practitioner_ID, src.Hygienist_Practitioner_ID,
            src.Dentist_Recall_Date, src.Dentist_Recall_Interval_Months,
            src.Hygienist_Recall_Date, src.Hygienist_Recall_Interval_Months,
            src.Recall_Method, src.Marketing_Consent, src.Custom_Field_1, src.Custom_Field_2,
            src.First_Appointment_Date, src.Last_Appointment_Date, src.Next_Appointment_Date,
            src.First_Exam_Date, src.Last_Exam_Date, src.Next_Exam_Date,
            src.Last_Scale_Polish_Date, src.Next_Scale_Polish_Date,
            src.Last_FTA_Date, src.Last_Cancelled_Appointment_Date,
            src.Total_Paid, src.Total_Invoiced, src.NHS_Exemption_Code,
            src.Patient_Created_Date, src.Patient_Updated_Date, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Patients tgt WHERE tgt.Patient_ID = src.Patient_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_Patients (pk_Patient, Tenant_ID, Patient_ID, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, -1, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Patients WHERE pk_Patient = -1);
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
