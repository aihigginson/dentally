--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Patients] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Patients
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     19/05/2026  AIH Add Emergency_Contact_Name/Relationship/Phone; read Archived_Reason from Bronze
--    *03     20/05/2026  AIH Preferred_Phone_Number is VARCHAR (enum: mobile/home/work) - remove float cast
--    *04     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *05     02/06/2026  AIH Bronze boolean columns are now VARCHAR; convert with LOWER(TRIM) IN ('true','1')
--    *06     17/06/2026  AIH DATA MINIMISATION (V011): drop special-category + excess-identifier columns;
--                            keep identity-for-contact, marketing consent + operational analytics only
--    *07     18/06/2026  AIH DATA MINIMISATION (V013): inactive patients (Active=0) -> name replaced with
--                            placeholder 'Inactive Patient', contact NULLed; PII held for active patients only
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
                    ISNULL(CAST(staged.[First_Name] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Last_Name] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Preferred_Name] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Email_Address] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Mobile_Phone] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Home_Phone] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Marketing_Opt_In] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Dentist_Practitioner_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Hygienist_Practitioner_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Payment_Plan_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Acquisition_Source_ID] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Dentist_Recall_Date] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Dentist_Recall_Interval] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Hygienist_Recall_Date] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Hygienist_Recall_Interval] AS VARCHAR(500)), ''),
                    ISNULL(CAST(staged.[Recall_Method] AS VARCHAR(500)), ''),
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
                    -- DATA MINIMISATION (V013): hold identifying/contact PII for ACTIVE patients only.
                    -- Inactive patients are no longer contactable: their real name is replaced with the
                    -- placeholder "Inactive Patient" (so they remain identifiable as such on reports) and
                    -- contact details are obfuscated to NULL. Non-identifying history is retained.
                    CASE WHEN LOWER(TRIM(Active)) IN ('true','1') THEN LEFT(First_Name,    100) ELSE 'Inactive' END AS First_Name,
                    CASE WHEN LOWER(TRIM(Active)) IN ('true','1') THEN LEFT(Last_Name,     100) ELSE 'Patient'  END AS Last_Name,
                    CASE WHEN LOWER(TRIM(Active)) IN ('true','1') THEN LEFT(Preferred_Name,100) END AS Preferred_Name,
                    CASE WHEN LOWER(TRIM(Active)) IN ('true','1') THEN Email_Address            END AS Email_Address,
                    CASE WHEN LOWER(TRIM(Active)) IN ('true','1') THEN LEFT(Mobile_Phone,   50) END AS Mobile_Phone,
                    CASE WHEN LOWER(TRIM(Active)) IN ('true','1') THEN LEFT(Home_Phone,     50) END AS Home_Phone,
                    -- Bronze Marketing is VARCHAR; map to Silver Marketing_Opt_In bit
                    CASE WHEN LOWER(TRIM(Marketing)) IN ('true','1')
                         THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END         AS Marketing_Opt_In,
                    TRY_CAST(ROUND(CAST(Dentist_ID AS float),0) AS int)      AS Dentist_Practitioner_ID,
                    TRY_CAST(ROUND(CAST(Hygienist_ID AS float),0) AS int)    AS Hygienist_Practitioner_ID,
                    Payment_Plan_ID                                          AS Payment_Plan_ID,
                    LEFT(Acquisition_Source_ID, 50)                          AS Acquisition_Source_ID,
                    TRY_CAST(Dentist_Recall_Date AS date)                    AS Dentist_Recall_Date,
                    TRY_CAST(ROUND(CAST(Dentist_Recall_Interval AS float),0) AS int)
                                                                             AS Dentist_Recall_Interval,
                    TRY_CAST(Hygienist_Recall_Date AS date)                  AS Hygienist_Recall_Date,
                    TRY_CAST(ROUND(CAST(Hygienist_Recall_Interval AS float),0) AS int)
                                                                             AS Hygienist_Recall_Interval,
                    LEFT(Recall_Method, 20)                                  AS Recall_Method,
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
            [First_Name] = src.[First_Name],
            [Last_Name] = src.[Last_Name],
            [Preferred_Name] = src.[Preferred_Name],
            [Email_Address] = src.[Email_Address],
            [Mobile_Phone] = src.[Mobile_Phone],
            [Home_Phone] = src.[Home_Phone],
            [Marketing_Opt_In] = src.[Marketing_Opt_In],
            [Dentist_Practitioner_ID] = src.[Dentist_Practitioner_ID],
            [Hygienist_Practitioner_ID] = src.[Hygienist_Practitioner_ID],
            [Payment_Plan_ID] = src.[Payment_Plan_ID],
            [Acquisition_Source_ID] = src.[Acquisition_Source_ID],
            [Dentist_Recall_Date] = src.[Dentist_Recall_Date],
            [Dentist_Recall_Interval] = src.[Dentist_Recall_Interval],
            [Hygienist_Recall_Date] = src.[Hygienist_Recall_Date],
            [Hygienist_Recall_Interval] = src.[Hygienist_Recall_Interval],
            [Recall_Method] = src.[Recall_Method],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Patients] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Patient_ID] = src.[Patient_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Patients] ([Tenant_ID], [Patient_ID], [Account_ID], [Site_ID], [Active], [First_Name], [Last_Name], [Preferred_Name], [Email_Address], [Mobile_Phone], [Home_Phone], [Marketing_Opt_In], [Dentist_Practitioner_ID], [Hygienist_Practitioner_ID], [Payment_Plan_ID], [Acquisition_Source_ID], [Dentist_Recall_Date], [Dentist_Recall_Interval], [Hygienist_Recall_Date], [Hygienist_Recall_Interval], [Recall_Method], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Patient_ID], src.[Account_ID], src.[Site_ID], src.[Active], src.[First_Name], src.[Last_Name], src.[Preferred_Name], src.[Email_Address], src.[Mobile_Phone], src.[Home_Phone], src.[Marketing_Opt_In], src.[Dentist_Practitioner_ID], src.[Hygienist_Practitioner_ID], src.[Payment_Plan_ID], src.[Acquisition_Source_ID], src.[Dentist_Recall_Date], src.[Dentist_Recall_Interval], src.[Hygienist_Recall_Date], src.[Hygienist_Recall_Interval], src.[Recall_Method], src.[Created_At], src.[Updated_At],
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
