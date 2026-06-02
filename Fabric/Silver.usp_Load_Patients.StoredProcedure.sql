--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Patients] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Patients
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     19/05/2026  AIH Add Emergency_Contact_Name/Relationship/Phone; read Archived_Reason from Bronze
--    *03     20/05/2026  AIH Preferred_Phone_Number is VARCHAR (enum: mobile/home/work) — remove float cast
--    *04     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *05     02/06/2026  AIH Bronze boolean columns are now VARCHAR; convert with LOWER(TRIM) IN ('true','1')
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Patients @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Patients]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Patients]
GO
CREATE PROCEDURE [Silver].[usp_Load_Patients]
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
            staged.*,
            CONVERT(VARBINARY(32), HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
                    ISNULL(CAST(staged.[Account_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Site_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Active] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Title] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[First_Name] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Middle_Name] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Last_Name] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Preferred_Name] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Preferred_Phone_Number] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Date_Of_Birth] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Gender] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Ethnicity] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[NHS_Number] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[NI_Number] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[PPS_Number] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Email_Address] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Mobile_Phone] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Mobile_Phone_Country] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Home_Phone] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Home_Phone_Country] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Work_Phone] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Work_Phone_Country] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Address_Line_1] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Address_Line_2] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Town] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[County] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Postcode] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Custom_Field_1] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Custom_Field_2] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Status] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Recalls] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Medical_Alert] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Medical_Alert_Text] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Sms_Communication] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Email_Communication] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Marketing_Opt_In] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Dentist_Practitioner_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Hygienist_Practitioner_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Payment_Plan_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Acquisition_Source_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Archived_Reason] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Consent_To_Share_Accounts] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Dentist_Recall_Date] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Dentist_Recall_Interval] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Hygienist_Recall_Date] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Hygienist_Recall_Interval] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Recall_Method] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Family_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Emergency_Contact_Name] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Emergency_Contact_Relationship] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Emergency_Contact_Phone] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), '')
                ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                    Tenant_ID  AS [Tenant_ID],
                    TRY_CAST(ROUND(CAST(Patient_ID AS float), 0) AS int)    AS Patient_ID,
                    TRY_CAST(ROUND(CAST(Account_ID AS float), 0) AS int)    AS Account_ID,
                    LEFT(Site_ID, 50)                                        AS Site_ID,
                    CASE WHEN LOWER(TRIM(Active)) IN ('true','1')
                         THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END         AS Active,
                    LEFT(Title,          20)                                 AS Title,
                    LEFT(First_Name,    100)                                 AS First_Name,
                    LEFT(Middle_Name,   100)                                 AS Middle_Name,
                    LEFT(Last_Name,     100)                                 AS Last_Name,
                    LEFT(Preferred_Name,100)                                 AS Preferred_Name,
                    LEFT(Preferred_Phone_Number, 50)                         AS Preferred_Phone_Number,
                    TRY_CAST(Date_Of_Birth AS date)                          AS Date_Of_Birth,
                    -- Bronze Gender is decimal; convert numeric code to text
                    CASE CAST(TRY_CAST(ROUND(CAST(Gender AS float),0) AS int) AS VARCHAR(5))
                        WHEN '0' THEN 'Unknown'
                        WHEN '1' THEN 'Male'
                        WHEN '2' THEN 'Female'
                        ELSE LEFT(CAST(Gender AS VARCHAR(20)), 20)
                    END                                                      AS Gender,
                    LEFT(CAST(TRY_CAST(ROUND(CAST(Ethnicity AS float),0) AS bigint) AS VARCHAR(50)), 50)
                                                                             AS Ethnicity,
                    LEFT(NHS_Number,  20)                                    AS NHS_Number,
                    LEFT(Ni_Number,   20)                                    AS NI_Number,
                    NULL                                                     AS PPS_Number,
                    Email_Address,
                    LEFT(Mobile_Phone,         50)                           AS Mobile_Phone,
                    LEFT(Mobile_Phone_Country, 50)                           AS Mobile_Phone_Country,
                    LEFT(Home_Phone,           50)                           AS Home_Phone,
                    LEFT(Home_Phone_Country,   50)                           AS Home_Phone_Country,
                    LEFT(Work_Phone,           50)                           AS Work_Phone,
                    LEFT(Work_Phone_Country,   50)                           AS Work_Phone_Country,
                    Address_Line_1,
                    Address_Line_2,
                    LEFT(Town,    100)                                       AS Town,
                    LEFT(County,  100)                                       AS County,
                    LEFT(Postcode, 20)                                       AS Postcode,
                    LEFT(Custom_Field_1, 100)                                AS Custom_Field_1,
                    LEFT(Custom_Field_2, 100)                                AS Custom_Field_2,
                    NULL                                                     AS Status,
                    CAST(NULL AS bit)                                         AS Recalls,
                    -- Bronze Medical_Alert is VARCHAR; Silver is bit
                    CASE WHEN LOWER(TRIM(Medical_Alert)) IN ('true','1')
                         THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END         AS Medical_Alert,
                    Medical_Alert_Text,
                    -- Bronze Use_Sms is VARCHAR; map to Silver Sms_Communication bit
                    CASE WHEN LOWER(TRIM(Use_Sms)) IN ('true','1')
                         THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END         AS Sms_Communication,
                    -- Bronze Use_Email is VARCHAR; map to Silver Email_Communication bit
                    CASE WHEN LOWER(TRIM(Use_Email)) IN ('true','1')
                         THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END         AS Email_Communication,
                    -- Bronze Marketing is VARCHAR; map to Silver Marketing_Opt_In bit
                    CASE WHEN LOWER(TRIM(Marketing)) IN ('true','1')
                         THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END         AS Marketing_Opt_In,
                    TRY_CAST(ROUND(CAST(Dentist_ID AS float),0) AS int)      AS Dentist_Practitioner_ID,
                    TRY_CAST(ROUND(CAST(Hygienist_ID AS float),0) AS int)    AS Hygienist_Practitioner_ID,
                    Payment_Plan_ID                                          AS Payment_Plan_ID,
                    LEFT(Acquisition_Source_ID, 50)                          AS Acquisition_Source_ID,
                    LEFT(Archived_Reason, 255)                               AS Archived_Reason,
                    CAST(NULL AS bit)                                         AS Consent_To_Share_Accounts,
                    TRY_CAST(Dentist_Recall_Date AS date)                    AS Dentist_Recall_Date,
                    TRY_CAST(ROUND(CAST(Dentist_Recall_Interval AS float),0) AS int)
                                                                             AS Dentist_Recall_Interval,
                    TRY_CAST(Hygienist_Recall_Date AS date)                  AS Hygienist_Recall_Date,
                    TRY_CAST(ROUND(CAST(Hygienist_Recall_Interval AS float),0) AS int)
                                                                             AS Hygienist_Recall_Interval,
                    LEFT(Recall_Method, 20)                                  AS Recall_Method,
                    LEFT(Family_ID,     20)                                  AS Family_ID,
                    LEFT(Emergency_Contact_Name,         255)                AS Emergency_Contact_Name,
                    LEFT(Emergency_Contact_Relationship, 255)                AS Emergency_Contact_Relationship,
                    LEFT(Emergency_Contact_Phone,        255)                AS Emergency_Contact_Phone,
                    LEFT(Created_At,    50)                                  AS Created_At,
                    LEFT(Updated_At,    50)                                  AS Updated_At
                FROM Bronze.Patients
                WHERE TRY_CAST(ROUND(CAST(Patient_ID AS float), 0) AS int) IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Account_ID] = src.[Account_ID],
            [Site_ID] = src.[Site_ID],
            [Active] = src.[Active],
            [Title] = src.[Title],
            [First_Name] = src.[First_Name],
            [Middle_Name] = src.[Middle_Name],
            [Last_Name] = src.[Last_Name],
            [Preferred_Name] = src.[Preferred_Name],
            [Preferred_Phone_Number] = src.[Preferred_Phone_Number],
            [Date_Of_Birth] = src.[Date_Of_Birth],
            [Gender] = src.[Gender],
            [Ethnicity] = src.[Ethnicity],
            [NHS_Number] = src.[NHS_Number],
            [NI_Number] = src.[NI_Number],
            [PPS_Number] = src.[PPS_Number],
            [Email_Address] = src.[Email_Address],
            [Mobile_Phone] = src.[Mobile_Phone],
            [Mobile_Phone_Country] = src.[Mobile_Phone_Country],
            [Home_Phone] = src.[Home_Phone],
            [Home_Phone_Country] = src.[Home_Phone_Country],
            [Work_Phone] = src.[Work_Phone],
            [Work_Phone_Country] = src.[Work_Phone_Country],
            [Address_Line_1] = src.[Address_Line_1],
            [Address_Line_2] = src.[Address_Line_2],
            [Town] = src.[Town],
            [County] = src.[County],
            [Postcode] = src.[Postcode],
            [Custom_Field_1] = src.[Custom_Field_1],
            [Custom_Field_2] = src.[Custom_Field_2],
            [Status] = src.[Status],
            [Recalls] = src.[Recalls],
            [Medical_Alert] = src.[Medical_Alert],
            [Medical_Alert_Text] = src.[Medical_Alert_Text],
            [Sms_Communication] = src.[Sms_Communication],
            [Email_Communication] = src.[Email_Communication],
            [Marketing_Opt_In] = src.[Marketing_Opt_In],
            [Dentist_Practitioner_ID] = src.[Dentist_Practitioner_ID],
            [Hygienist_Practitioner_ID] = src.[Hygienist_Practitioner_ID],
            [Payment_Plan_ID] = src.[Payment_Plan_ID],
            [Acquisition_Source_ID] = src.[Acquisition_Source_ID],
            [Archived_Reason] = src.[Archived_Reason],
            [Consent_To_Share_Accounts] = src.[Consent_To_Share_Accounts],
            [Dentist_Recall_Date] = src.[Dentist_Recall_Date],
            [Dentist_Recall_Interval] = src.[Dentist_Recall_Interval],
            [Hygienist_Recall_Date] = src.[Hygienist_Recall_Date],
            [Hygienist_Recall_Interval] = src.[Hygienist_Recall_Interval],
            [Recall_Method] = src.[Recall_Method],
            [Family_ID] = src.[Family_ID],
            [Emergency_Contact_Name] = src.[Emergency_Contact_Name],
            [Emergency_Contact_Relationship] = src.[Emergency_Contact_Relationship],
            [Emergency_Contact_Phone] = src.[Emergency_Contact_Phone],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Patients] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Patient_ID] = src.[Patient_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Patients] ([Tenant_ID], [Patient_ID], [Account_ID], [Site_ID], [Active], [Title], [First_Name], [Middle_Name], [Last_Name], [Preferred_Name], [Preferred_Phone_Number], [Date_Of_Birth], [Gender], [Ethnicity], [NHS_Number], [NI_Number], [PPS_Number], [Email_Address], [Mobile_Phone], [Mobile_Phone_Country], [Home_Phone], [Home_Phone_Country], [Work_Phone], [Work_Phone_Country], [Address_Line_1], [Address_Line_2], [Town], [County], [Postcode], [Custom_Field_1], [Custom_Field_2], [Status], [Recalls], [Medical_Alert], [Medical_Alert_Text], [Sms_Communication], [Email_Communication], [Marketing_Opt_In], [Dentist_Practitioner_ID], [Hygienist_Practitioner_ID], [Payment_Plan_ID], [Acquisition_Source_ID], [Archived_Reason], [Consent_To_Share_Accounts], [Dentist_Recall_Date], [Dentist_Recall_Interval], [Hygienist_Recall_Date], [Hygienist_Recall_Interval], [Recall_Method], [Family_ID], [Emergency_Contact_Name], [Emergency_Contact_Relationship], [Emergency_Contact_Phone], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Patient_ID], src.[Account_ID], src.[Site_ID], src.[Active], src.[Title], src.[First_Name], src.[Middle_Name], src.[Last_Name], src.[Preferred_Name], src.[Preferred_Phone_Number], src.[Date_Of_Birth], src.[Gender], src.[Ethnicity], src.[NHS_Number], src.[NI_Number], src.[PPS_Number], src.[Email_Address], src.[Mobile_Phone], src.[Mobile_Phone_Country], src.[Home_Phone], src.[Home_Phone_Country], src.[Work_Phone], src.[Work_Phone_Country], src.[Address_Line_1], src.[Address_Line_2], src.[Town], src.[County], src.[Postcode], src.[Custom_Field_1], src.[Custom_Field_2], src.[Status], src.[Recalls], src.[Medical_Alert], src.[Medical_Alert_Text], src.[Sms_Communication], src.[Email_Communication], src.[Marketing_Opt_In], src.[Dentist_Practitioner_ID], src.[Hygienist_Practitioner_ID], src.[Payment_Plan_ID], src.[Acquisition_Source_ID], src.[Archived_Reason], src.[Consent_To_Share_Accounts], src.[Dentist_Recall_Date], src.[Dentist_Recall_Interval], src.[Hygienist_Recall_Date], src.[Hygienist_Recall_Interval], src.[Recall_Method], src.[Family_ID], src.[Emergency_Contact_Name], src.[Emergency_Contact_Relationship], src.[Emergency_Contact_Phone], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Patients] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Patient_ID] = src.[Patient_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Patients] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Patient_ID] = tgt.[Patient_ID]
        );
        SET @My_Deletes = @@ROWCOUNT;

        DROP TABLE IF EXISTS #src;

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
