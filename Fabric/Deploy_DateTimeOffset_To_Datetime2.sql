USE [Dentally];
GO
SET NOCOUNT ON;

PRINT '=== Step 1: Alter Silver columns datetimeoffset(3) -> datetime2(3) ===';

ALTER TABLE [Silver].[Invoices]       ALTER COLUMN [Sent_At]                  datetime2(3) NULL;
ALTER TABLE [Silver].[NHS_Claims]     ALTER COLUMN [Nhs_Updated_At]           datetime2(3) NULL;
ALTER TABLE [Silver].[Payment_Plans]  ALTER COLUMN [Payment_Plan_Created_At]  datetime2(3) NULL;
ALTER TABLE [Silver].[Recalls]        ALTER COLUMN [Sent_At]                  datetime2(3) NULL;
ALTER TABLE [Silver].[Recalls]        ALTER COLUMN [Booked_At]                datetime2(3) NULL;

PRINT '=== Step 2: Alter Gold columns datetimeoffset(3) -> datetime2(3) ===';

ALTER TABLE [Gold].[Dim_Payment_Plans]          ALTER COLUMN [Created_Date]         datetime2(3) NULL;
ALTER TABLE [Gold].[Dim_Practitioners]          ALTER COLUMN [Created_Date]         datetime2(3) NULL;
ALTER TABLE [Gold].[Dim_Practitioners]          ALTER COLUMN [Updated_Date]         datetime2(3) NULL;
ALTER TABLE [Gold].[Dim_Treatment_Plans]        ALTER COLUMN [Completed_Date]       datetime2(3) NULL;
ALTER TABLE [Gold].[Dim_Treatment_Plans]        ALTER COLUMN [Created_Date]         datetime2(3) NULL;
ALTER TABLE [Gold].[Dim_Treatment_Plans]        ALTER COLUMN [Updated_Date]         datetime2(3) NULL;
ALTER TABLE [Gold].[Dim_Treatments]             ALTER COLUMN [Created_Date]         datetime2(3) NULL;
ALTER TABLE [Gold].[Dim_Treatments]             ALTER COLUMN [Updated_Date]         datetime2(3) NULL;
ALTER TABLE [Gold].[Dim_Users]                  ALTER COLUMN [Created_Date]         datetime2(3) NULL;
ALTER TABLE [Gold].[Dim_Users]                  ALTER COLUMN [Updated_Date]         datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Appointments]          ALTER COLUMN [Arrived_At]           datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Appointments]          ALTER COLUMN [In_Surgery_At]        datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Appointments]          ALTER COLUMN [Completed_At]         datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Appointments]          ALTER COLUMN [Confirmed_At]         datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Appointments]          ALTER COLUMN [Cancelled_At]         datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Appointments]          ALTER COLUMN [Did_Not_Attend_At]    datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Appointments]          ALTER COLUMN [Start_Time]           datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Appointments]          ALTER COLUMN [Finish_Time]          datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Appointments]          ALTER COLUMN [Pending_At]           datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Treatment_Appointments] ALTER COLUMN [Created_At]          datetime2(3) NULL;
ALTER TABLE [Gold].[Fact_Treatment_Appointments] ALTER COLUMN [Updated_At]          datetime2(3) NULL;

PRINT '=== Step 3: Redeploy Silver stored procedure (Payment_Plans) ===';
GO

CREATE OR ALTER PROCEDURE [Silver].[usp_Load_Payment_Plans]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       TINYINT      = 1
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
            HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
        ISNULL(CAST(staged.[Payment_Plan_Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Colour] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Dentist_Recall_Interval] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Emergency_Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Exam_Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Exam_Scale_And_Polish_Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Hygienist_Recall_Interval] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Patient_Friendly_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Scale_And_Polish_Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Created_At] AS VARCHAR(500)), '')
        )) AS _Hash
        INTO #src
        FROM (
            SELECT
                Payment_Plan_ID  AS [Payment_Plan_Id],
                LEFT(Payment_Plan_Site_ID, 50)  AS [Payment_Plan_Site_Id],
                CASE WHEN TRY_CAST(Payment_Plan_Active AS decimal(18,4)) = 1
             THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Payment_Plan_Active],
                LEFT(Payment_Plan_Colour, 20)  AS [Payment_Plan_Colour],
                TRY_CAST(ROUND(CAST(Dentist_Recall_Interval AS float), 0) AS int)  AS [Dentist_Recall_Interval],
                TRY_CAST(ROUND(CAST(Emergency_Duration AS float), 0) AS int)  AS [Emergency_Duration],
                TRY_CAST(ROUND(CAST(Exam_Duration AS float), 0) AS int)  AS [Exam_Duration],
                TRY_CAST(ROUND(CAST(Exam_Scale_And_Polish_Duration AS float), 0) AS int)  AS [Exam_Scale_And_Polish_Duration],
                TRY_CAST(ROUND(CAST(Hygienist_Recall_Interval AS float), 0) AS int)  AS [Hygienist_Recall_Interval],
                Payment_Plan_Name  AS [Payment_Plan_Name],
                Payment_Plan_Patient_Friendly_Name  AS [Payment_Plan_Patient_Friendly_Name],
                TRY_CAST(ROUND(CAST(Scale_And_Polish_Duration AS float), 0) AS int)  AS [Scale_And_Polish_Duration],
                TRY_CAST(Payment_Plan_Created_At AS datetime2(3))  AS [Payment_Plan_Created_At]
            FROM Bronze.Payment_Plans
        ) AS staged;

        UPDATE tgt
        SET
            [Payment_Plan_Site_Id] = src.[Payment_Plan_Site_Id],
            [Payment_Plan_Active] = src.[Payment_Plan_Active],
            [Payment_Plan_Colour] = src.[Payment_Plan_Colour],
            [Dentist_Recall_Interval] = src.[Dentist_Recall_Interval],
            [Emergency_Duration] = src.[Emergency_Duration],
            [Exam_Duration] = src.[Exam_Duration],
            [Exam_Scale_And_Polish_Duration] = src.[Exam_Scale_And_Polish_Duration],
            [Hygienist_Recall_Interval] = src.[Hygienist_Recall_Interval],
            [Payment_Plan_Name] = src.[Payment_Plan_Name],
            [Payment_Plan_Patient_Friendly_Name] = src.[Payment_Plan_Patient_Friendly_Name],
            [Scale_And_Polish_Duration] = src.[Scale_And_Polish_Duration],
            [Payment_Plan_Created_At] = src.[Payment_Plan_Created_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Payment_Plans] AS tgt
        INNER JOIN #src AS src ON tgt.[Payment_Plan_Id] = src.[Payment_Plan_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Payment_Plans] ([Payment_Plan_Id], [Payment_Plan_Site_Id], [Payment_Plan_Active], [Payment_Plan_Colour], [Dentist_Recall_Interval], [Emergency_Duration], [Exam_Duration], [Exam_Scale_And_Polish_Duration], [Hygienist_Recall_Interval], [Payment_Plan_Name], [Payment_Plan_Patient_Friendly_Name], [Scale_And_Polish_Duration], [Payment_Plan_Created_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Payment_Plan_Id], src.[Payment_Plan_Site_Id], src.[Payment_Plan_Active], src.[Payment_Plan_Colour], src.[Dentist_Recall_Interval], src.[Emergency_Duration], src.[Exam_Duration], src.[Exam_Scale_And_Polish_Duration], src.[Hygienist_Recall_Interval], src.[Payment_Plan_Name], src.[Payment_Plan_Patient_Friendly_Name], src.[Scale_And_Polish_Duration], src.[Payment_Plan_Created_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Payment_Plans] AS tgt WHERE tgt.[Payment_Plan_Id] = src.[Payment_Plan_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Payment_Plans] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Payment_Plan_Id] = tgt.[Payment_Plan_Id]
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

PRINT '=== Step 4: Redeploy Gold stored procedures ===';
GO

CREATE OR ALTER PROCEDURE [Gold].[usp_Load_Dim_Payment_Plans]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       TINYINT      = 1
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
            CAST(payment_plan_id AS INT)                                    AS Payment_Plan_ID,
            NULLIF(TRIM(payment_plan_name),'')                              AS Payment_Plan_Name,
            NULLIF(TRIM(payment_plan_patient_friendly_name),'')             AS Patient_Friendly_Name,
            CAST(ISNULL(payment_plan_active,0) AS BIT)                      AS Active,
            NULLIF(TRIM(payment_plan_colour),'')                            AS Colour,
            NULLIF(TRIM(payment_plan_site_id),'')                           AS Site_ID,
            CAST(dentist_recall_interval AS INT)                            AS Dentist_Recall_Interval_Months,
            CAST(hygienist_recall_interval AS INT)                          AS Hygienist_Recall_Interval_Months,
            CAST(emergency_duration AS INT)                                 AS Emergency_Duration_Mins,
            CAST(exam_duration AS INT)                                      AS Exam_Duration_Mins,
            CAST(exam_scale_and_polish_duration AS INT)                     AS Exam_Scale_Polish_Duration_Mins,
            CAST(scale_and_polish_duration AS INT)                          AS Scale_Polish_Duration_Mins,
            TRY_CAST(payment_plan_created_at AS datetime2(3))               AS Created_Date
        INTO #src
        FROM Silver.payment_plans
        WHERE payment_plan_id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Payment_Plans tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Payment_Plan_ID = tgt.Payment_Plan_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Payment_Plan_Name               = src.Payment_Plan_Name,
            Patient_Friendly_Name           = src.Patient_Friendly_Name,
            Active                          = src.Active,
            Colour                          = src.Colour,
            Site_ID                         = src.Site_ID,
            Dentist_Recall_Interval_Months  = src.Dentist_Recall_Interval_Months,
            Hygienist_Recall_Interval_Months= src.Hygienist_Recall_Interval_Months,
            Emergency_Duration_Mins         = src.Emergency_Duration_Mins,
            Exam_Duration_Mins              = src.Exam_Duration_Mins,
            Exam_Scale_Polish_Duration_Mins = src.Exam_Scale_Polish_Duration_Mins,
            Scale_Polish_Duration_Mins      = src.Scale_Polish_Duration_Mins,
            DW_Updated_At                   = GETDATE()
        FROM Gold.Dim_Payment_Plans tgt
        INNER JOIN #src src ON tgt.Payment_Plan_ID = src.Payment_Plan_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Payment_Plan_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Friendly_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Colour] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Emergency_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Exam_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Exam_Scale_Polish_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Scale_Polish_Duration_Mins] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Payment_Plan_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Friendly_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Colour] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Dentist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Emergency_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Exam_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Exam_Scale_Polish_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Scale_Polish_Duration_Mins] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Dim_Payment_Plans (
            Payment_Plan_ID, Payment_Plan_Name, Patient_Friendly_Name, Active, Colour, Site_ID,
            Dentist_Recall_Interval_Months, Hygienist_Recall_Interval_Months,
            Emergency_Duration_Mins, Exam_Duration_Mins, Exam_Scale_Polish_Duration_Mins,
            Scale_Polish_Duration_Mins, Created_Date, DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Payment_Plan_ID, src.Payment_Plan_Name, src.Patient_Friendly_Name, src.Active, src.Colour, src.Site_ID,
            src.Dentist_Recall_Interval_Months, src.Hygienist_Recall_Interval_Months,
            src.Emergency_Duration_Mins, src.Exam_Duration_Mins, src.Exam_Scale_Polish_Duration_Mins,
            src.Scale_Polish_Duration_Mins, src.Created_Date, GETDATE(), GETDATE()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Payment_Plans tgt WHERE tgt.Payment_Plan_ID = src.Payment_Plan_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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

CREATE OR ALTER PROCEDURE [Gold].[usp_Load_Dim_Practitioners]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       TINYINT      = 1
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
            CAST(practitioner_id AS INT)                                    AS Practitioner_ID,
            CAST(user_id AS INT)                                            AS User_ID,
            NULLIF(TRIM(user_title),'')                                     AS Title,
            NULLIF(TRIM(user_first_name),'')                                AS First_Name,
            NULLIF(TRIM(user_middle_name),'')                               AS Middle_Name,
            NULLIF(TRIM(user_last_name),'')                                 AS Last_Name,
            NULLIF(CONCAT_WS(' ',
                NULLIF(TRIM(user_title),''),
                NULLIF(TRIM(user_first_name),''),
                NULLIF(TRIM(user_last_name),'')),'')                        AS Full_Name,
            NULLIF(TRIM(user_email),'')                                     AS Email,
            NULLIF(TRIM(user_mobile_phone),'')                              AS Mobile_Phone,
            NULLIF(TRIM(user_role),'')                                      AS Role,
            CAST(user_permission_level AS INT)                              AS Permission_Level,
            CAST(ISNULL(practitioner_active,0) AS BIT)                      AS Active,
            NULLIF(TRIM(practitioner_colour),'')                            AS Colour,
            NULLIF(TRIM(practitioner_gdc_number),'')                        AS GDC_Number,
            NULLIF(TRIM(practitioner_nhs_number),'')                        AS NHS_Number,
            NULLIF(TRIM(practitioner_site_id),'')                           AS Site_ID,
            NULLIF(TRIM(practitioner_default_contract_id),'')               AS Default_Contract_ID,
            NULLIF(TRIM(contract_targets_string),'')                        AS Contract_Targets_String,
            NULLIF(TRIM(user_image_url),'')                                 AS Image_URL,
            TRY_CAST(NULLIF(TRIM(user_last_login),'') AS DATE)              AS Last_Login_Date,
            TRY_CAST(NULLIF(TRIM(user_created_at),'') AS datetime2(3))      AS Created_Date,
            TRY_CAST(NULLIF(TRIM(user_updated_at),'') AS datetime2(3))      AS Updated_Date
        INTO #src
        FROM Silver.practitioners
        WHERE practitioner_id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Practitioners tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Practitioner_ID = tgt.Practitioner_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            User_ID                 = src.User_ID,
            Title                   = src.Title,
            First_Name              = src.First_Name,
            Middle_Name             = src.Middle_Name,
            Last_Name               = src.Last_Name,
            Full_Name               = src.Full_Name,
            Email                   = src.Email,
            Mobile_Phone            = src.Mobile_Phone,
            Role                    = src.Role,
            Permission_Level        = src.Permission_Level,
            Active                  = src.Active,
            Colour                  = src.Colour,
            GDC_Number              = src.GDC_Number,
            NHS_Number              = src.NHS_Number,
            Site_ID                 = src.Site_ID,
            Default_Contract_ID     = src.Default_Contract_ID,
            Contract_Targets_String = src.Contract_Targets_String,
            Image_URL               = src.Image_URL,
            Last_Login_Date         = src.Last_Login_Date,
            Updated_Date            = src.Updated_Date,
            DW_Updated_At           = GETDATE()
        FROM Gold.Dim_Practitioners tgt
        INNER JOIN #src src ON tgt.Practitioner_ID = src.Practitioner_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[User_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Title] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Middle_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Role] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Permission_Level] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Colour] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[GDC_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Default_Contract_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Contract_Targets_String] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Image_URL] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Login_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_Date] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[User_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Title] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Middle_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Role] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Permission_Level] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Colour] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[GDC_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Default_Contract_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Contract_Targets_String] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Image_URL] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Login_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_Date] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Dim_Practitioners (
            Practitioner_ID, User_ID, Title, First_Name, Middle_Name, Last_Name, Full_Name,
            Email, Mobile_Phone, Role, Permission_Level, Active, Colour, GDC_Number, NHS_Number,
            Site_ID, Default_Contract_ID, Contract_Targets_String, Image_URL,
            Last_Login_Date, Created_Date, Updated_Date, DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Practitioner_ID, src.User_ID, src.Title, src.First_Name, src.Middle_Name, src.Last_Name, src.Full_Name,
            src.Email, src.Mobile_Phone, src.Role, src.Permission_Level, src.Active, src.Colour, src.GDC_Number, src.NHS_Number,
            src.Site_ID, src.Default_Contract_ID, src.Contract_Targets_String, src.Image_URL,
            src.Last_Login_Date, src.Created_Date, src.Updated_Date, GETDATE(), GETDATE()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Practitioners tgt WHERE tgt.Practitioner_ID = src.Practitioner_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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

CREATE OR ALTER PROCEDURE [Gold].[usp_Load_Dim_Treatment_Plans]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       TINYINT      = 1
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
            CAST(id AS INT)                                             AS Treatment_Plan_ID,
            NULLIF(TRIM(nickname),'')                                   AS Nickname,
            CAST(patient_id AS INT)                                     AS Patient_ID,
            CAST(practitioner_id AS INT)                                AS Practitioner_ID,
            CAST(ISNULL(completed,0) AS BIT)                            AS Completed,
            CAST(start_date AS DATE)                                    AS Start_Date,
            CAST(end_date AS DATE)                                      AS End_Date,
            TRY_CAST(NULLIF(TRIM(completed_at),'') AS datetime2(3))     AS Completed_Date,
            TRY_CAST(NULLIF(TRIM(last_completed_at),'') AS DATE)        AS Last_Completed_Date,
            CAST(ISNULL(nhs_uda_value,0) AS DECIMAL(10,2))              AS NHS_UDA_Value,
            CAST(ISNULL(nhs_completed_uda_value,0) AS DECIMAL(10,2))    AS NHS_Completed_UDA_Value,
            CAST(ISNULL(private_treatment_value,0) AS DECIMAL(12,2))    AS Private_Treatment_Value,
            TRY_CAST(NULLIF(TRIM(created_at),'') AS datetime2(3))       AS Created_Date,
            TRY_CAST(NULLIF(TRIM(updated_at),'') AS datetime2(3))       AS Updated_Date
        INTO #src
        FROM Silver.treatment_plans
        WHERE id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Treatment_Plans tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Treatment_Plan_ID = tgt.Treatment_Plan_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Nickname                = src.Nickname,
            Patient_ID              = src.Patient_ID,
            Practitioner_ID         = src.Practitioner_ID,
            Completed               = src.Completed,
            Start_Date              = src.Start_Date,
            End_Date                = src.End_Date,
            Completed_Date          = src.Completed_Date,
            Last_Completed_Date     = src.Last_Completed_Date,
            NHS_UDA_Value           = src.NHS_UDA_Value,
            NHS_Completed_UDA_Value = src.NHS_Completed_UDA_Value,
            Private_Treatment_Value = src.Private_Treatment_Value,
            Updated_Date            = src.Updated_Date,
            DW_Updated_At           = GETDATE()
        FROM Gold.Dim_Treatment_Plans tgt
        INNER JOIN #src src ON tgt.Treatment_Plan_ID = src.Treatment_Plan_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Nickname] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practitioner_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Start_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[End_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Completed_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Completed_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Completed_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Private_Treatment_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_Date] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Nickname] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practitioner_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Start_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[End_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Completed_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Completed_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Completed_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Private_Treatment_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_Date] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Dim_Treatment_Plans (
            Treatment_Plan_ID, Nickname, Patient_ID, Practitioner_ID, Completed,
            Start_Date, End_Date, Completed_Date, Last_Completed_Date,
            NHS_UDA_Value, NHS_Completed_UDA_Value, Private_Treatment_Value,
            Created_Date, Updated_Date, DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Treatment_Plan_ID, src.Nickname, src.Patient_ID, src.Practitioner_ID, src.Completed,
            src.Start_Date, src.End_Date, src.Completed_Date, src.Last_Completed_Date,
            src.NHS_UDA_Value, src.NHS_Completed_UDA_Value, src.Private_Treatment_Value,
            src.Created_Date, src.Updated_Date, GETDATE(), GETDATE()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Treatment_Plans tgt WHERE tgt.Treatment_Plan_ID = src.Treatment_Plan_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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

CREATE OR ALTER PROCEDURE [Gold].[usp_Load_Dim_Treatments]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       TINYINT      = 1
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
            CAST(t.id AS INT)                               AS Treatment_ID,
            CAST(t.code AS INT)                             AS Treatment_Code,
            NULLIF(TRIM(t.nomenclature),'')                 AS Nomenclature,
            NULLIF(TRIM(t.patient_nomenclature),'')         AS Patient_Nomenclature,
            NULLIF(TRIM(t.description),'')                  AS Description,
            NULLIF(TRIM(t.patient_description),'')          AS Patient_Description,
            NULLIF(TRIM(t.notes),'')                        AS Notes,
            NULLIF(TRIM(t.region),'')                       AS Region,
            CAST(t.uda_band AS INT)                         AS UDA_Band,
            CAST(t.nhs_treatment_cat AS INT)                AS NHS_Treatment_Cat,
            CAST(t.treatment_category_id AS INT)            AS Treatment_Category_ID,
            NULLIF(TRIM(tc.name),'')                        AS Treatment_Category_Name,
            TRY_CAST(NULLIF(TRIM(t.created_at),'') AS datetime2(3)) AS Created_Date,
            TRY_CAST(NULLIF(TRIM(t.updated_at),'') AS datetime2(3)) AS Updated_Date
        INTO #src
        FROM Silver.treatments t
        LEFT JOIN Silver.treatment_categories tc ON tc.id = t.treatment_category_id
        WHERE t.id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Treatments tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Treatment_ID = tgt.Treatment_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Treatment_Code          = src.Treatment_Code,
            Nomenclature            = src.Nomenclature,
            Patient_Nomenclature    = src.Patient_Nomenclature,
            Description             = src.Description,
            Patient_Description     = src.Patient_Description,
            Notes                   = src.Notes,
            Region                  = src.Region,
            UDA_Band                = src.UDA_Band,
            NHS_Treatment_Cat       = src.NHS_Treatment_Cat,
            Treatment_Category_ID   = src.Treatment_Category_ID,
            Treatment_Category_Name = src.Treatment_Category_Name,
            Updated_Date            = src.Updated_Date,
            DW_Updated_At           = GETDATE()
        FROM Gold.Dim_Treatments tgt
        INNER JOIN #src src ON tgt.Treatment_ID = src.Treatment_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Treatment_Code] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Nomenclature] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Nomenclature] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Region] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UDA_Band] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Treatment_Cat] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Category_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Category_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_Date] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Treatment_Code] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Nomenclature] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Nomenclature] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Region] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UDA_Band] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Treatment_Cat] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Category_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Category_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_Date] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Dim_Treatments (
            Treatment_ID, Treatment_Code, Nomenclature, Patient_Nomenclature, Description,
            Patient_Description, Notes, Region, UDA_Band, NHS_Treatment_Cat,
            Treatment_Category_ID, Treatment_Category_Name, Created_Date, Updated_Date,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Treatment_ID, src.Treatment_Code, src.Nomenclature, src.Patient_Nomenclature, src.Description,
            src.Patient_Description, src.Notes, src.Region, src.UDA_Band, src.NHS_Treatment_Cat,
            src.Treatment_Category_ID, src.Treatment_Category_Name, src.Created_Date, src.Updated_Date,
            GETDATE(), GETDATE()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Treatments tgt WHERE tgt.Treatment_ID = src.Treatment_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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

CREATE OR ALTER PROCEDURE [Gold].[usp_Load_Dim_Users]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       TINYINT      = 1
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
            CAST(id AS INT)                                     AS bk_User_ID,
            NULLIF(TRIM(title), '')                             AS Title,
            NULLIF(TRIM(first_name), '')                        AS First_Name,
            NULLIF(TRIM(middle_name), '')                       AS Middle_Name,
            NULLIF(TRIM(last_name), '')                         AS Last_Name,
            NULLIF(CONCAT_WS(' ',
                NULLIF(TRIM(title),''),
                NULLIF(TRIM(first_name),''),
                NULLIF(TRIM(middle_name),''),
                NULLIF(TRIM(last_name),'')),'')                 AS Full_Name,
            NULLIF(TRIM(email), '')                             AS Email,
            NULLIF(TRIM(mobile_phone), '')                      AS Mobile_Phone,
            NULLIF(TRIM(role), '')                              AS Role,
            CAST(permission_level AS INT)                       AS Permission_Level,
            NULLIF(TRIM(practice_id), '')                       AS Practice_ID,
            NULLIF(TRIM(site_id), '')                           AS Site_ID,
            NULLIF(TRIM(image_url), '')                         AS Image_URL,
            TRY_CAST(NULLIF(TRIM(last_login),'') AS DATE)       AS Last_Login_Date,
            TRY_CAST(NULLIF(TRIM(created_at),'') AS datetime2(3)) AS Created_Date,
            TRY_CAST(NULLIF(TRIM(updated_at),'') AS datetime2(3)) AS Updated_Date
        INTO #src
        FROM Silver.users
        WHERE id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Users tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_User_ID = tgt.bk_User_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Title               = src.Title,
            First_Name          = src.First_Name,
            Middle_Name         = src.Middle_Name,
            Last_Name           = src.Last_Name,
            Full_Name           = src.Full_Name,
            Email               = src.Email,
            Mobile_Phone        = src.Mobile_Phone,
            Role                = src.Role,
            Permission_Level    = src.Permission_Level,
            Practice_ID         = src.Practice_ID,
            Site_ID             = src.Site_ID,
            Image_URL           = src.Image_URL,
            Last_Login_Date     = src.Last_Login_Date,
            Created_Date        = src.Created_Date,
            Updated_Date        = src.Updated_Date,
            DW_Updated_At       = GETDATE()
        FROM Gold.Dim_Users tgt
        INNER JOIN #src src ON tgt.bk_User_ID = src.bk_User_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Title] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Middle_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Role] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Permission_Level] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Image_URL] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Login_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Created_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_Date] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Title] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Middle_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Role] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Permission_Level] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Image_URL] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Login_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Created_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_Date] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Dim_Users (
            bk_User_ID, Title, First_Name, Middle_Name, Last_Name, Full_Name,
            Email, Mobile_Phone, Role, Permission_Level, Practice_ID, Site_ID,
            Image_URL, Last_Login_Date, Created_Date, Updated_Date,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.bk_User_ID, src.Title, src.First_Name, src.Middle_Name, src.Last_Name, src.Full_Name,
            src.Email, src.Mobile_Phone, src.Role, src.Permission_Level, src.Practice_ID, src.Site_ID,
            src.Image_URL, src.Last_Login_Date, src.Created_Date, src.Updated_Date,
            GETDATE(), GETDATE()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Users tgt WHERE tgt.bk_User_ID = src.bk_User_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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

CREATE OR ALTER PROCEDURE [Gold].[usp_Load_Fact_Appointments]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       TINYINT      = 1
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
            CAST(a.appointment_id AS INT)                               AS bk_Appointment_ID,

            dpat.pk_Patient                                             AS fk_Patient,
            dpr.pk_Practitioner                                         AS fk_Practitioner,
            dpp.pk_Payment_Plan                                         AS fk_Payment_Plan,
            dps.pk_Practice_Site                                        AS fk_Practice_Site,
            du.pk_User                                                  AS fk_User,

            dd_s.pk_Date                                                AS fk_Date_Start,
            dd_p.pk_Date                                                AS fk_Date_Pending,
            dd_c.pk_Date                                                AS fk_Date_Created,

            NULLIF(TRIM(a.room_id),'')                                  AS Room_ID,
            NULLIF(TRIM(a.state),'')                                    AS State,
            NULLIF(TRIM(a.reason),'')                                   AS Reason,
            NULLIF(TRIM(a.treatment_description),'')                    AS Treatment_Description,
            NULLIF(TRIM(a.notes),'')                                    AS Notes,
            a.appointment_cancellation_reason_id                        AS Cancellation_Reason_ID,

            TRY_CAST(NULLIF(TRIM(a.arrived_at),'') AS datetime2(3))         AS Arrived_At,
            TRY_CAST(NULLIF(TRIM(a.in_surgery_at),'') AS datetime2(3))      AS In_Surgery_At,
            TRY_CAST(NULLIF(TRIM(a.completed_at),'') AS datetime2(3))       AS Completed_At,
            TRY_CAST(NULLIF(TRIM(a.confirmed_at),'') AS datetime2(3))       AS Confirmed_At,
            TRY_CAST(NULLIF(TRIM(a.cancelled_at),'') AS datetime2(3))       AS Cancelled_At,
            TRY_CAST(NULLIF(TRIM(a.did_not_attend_at),'') AS datetime2(3))  AS Did_Not_Attend_At,

            TRY_CAST(NULLIF(TRIM(a.start_time),'') AS datetime2(3))         AS Start_Time,
            TRY_CAST(NULLIF(TRIM(a.finish_time),'') AS datetime2(3))        AS Finish_Time,
            TRY_CAST(NULLIF(TRIM(a.pending_at),'') AS datetime2(3))         AS Pending_At,

            CASE WHEN a.completed_at IS NOT NULL THEN 1 ELSE 0 END      AS Is_Completed,
            CASE WHEN a.cancelled_at IS NOT NULL THEN 1 ELSE 0 END      AS Is_Cancelled,
            CASE WHEN a.did_not_attend_at IS NOT NULL THEN 1 ELSE 0 END AS Is_DNA,
            CASE WHEN a.arrived_at IS NOT NULL THEN 1 ELSE 0 END        AS Is_Arrived,

            CAST(ISNULL(a.duration,0) AS INT)                           AS Duration_Mins,

            CASE WHEN a.arrived_at IS NOT NULL AND a.in_surgery_at IS NOT NULL
                 THEN DATEDIFF(MINUTE,
                        TRY_CAST(NULLIF(TRIM(a.arrived_at),'') AS datetime2(3)),
                        TRY_CAST(NULLIF(TRIM(a.in_surgery_at),'') AS datetime2(3)))
            END                                                         AS Waiting_Mins,

            CASE WHEN a.in_surgery_at IS NOT NULL AND a.completed_at IS NOT NULL
                 THEN DATEDIFF(MINUTE,
                        TRY_CAST(NULLIF(TRIM(a.in_surgery_at),'') AS datetime2(3)),
                        TRY_CAST(NULLIF(TRIM(a.completed_at),'') AS datetime2(3)))
            END                                                         AS In_Surgery_Mins
        INTO #src
        FROM Silver.appointments a
        LEFT JOIN Gold.Dim_Patients dpat        ON dpat.Patient_ID      = a.patient_id
        LEFT JOIN Gold.Dim_Practitioners dpr    ON dpr.Practitioner_ID  = CAST(a.practitioner_id AS INT)
        LEFT JOIN Gold.Dim_Payment_Plans dpp    ON dpp.Payment_Plan_ID  = CAST(a.payment_plan_id AS INT)
        LEFT JOIN Gold.Dim_Practice_Sites dps   ON dps.Site_ID          = NULLIF(TRIM(a.room_id),'')
        LEFT JOIN Gold.Dim_Users du             ON du.bk_User_ID        = CAST(a.user_id AS INT)
        LEFT JOIN Gold.Dim_Date dd_s            ON dd_s.Full_Date       = TRY_CAST(NULLIF(TRIM(a.start_time),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_p            ON dd_p.Full_Date       = TRY_CAST(NULLIF(TRIM(a.pending_at),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_c            ON dd_c.Full_Date       = CAST(a.created_at AS DATE)
        WHERE a.appointment_id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Appointments tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Appointment_ID = tgt.bk_Appointment_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Patient              = src.fk_Patient,
            fk_Practitioner         = src.fk_Practitioner,
            fk_Payment_Plan         = src.fk_Payment_Plan,
            fk_Practice_Site        = src.fk_Practice_Site,
            fk_User                 = src.fk_User,
            fk_Date_Start           = src.fk_Date_Start,
            fk_Date_Pending         = src.fk_Date_Pending,
            fk_Date_Created         = src.fk_Date_Created,
            Room_ID                 = src.Room_ID,
            State                   = src.State,
            Reason                  = src.Reason,
            Treatment_Description   = src.Treatment_Description,
            Notes                   = src.Notes,
            Cancellation_Reason_ID  = src.Cancellation_Reason_ID,
            Arrived_At              = src.Arrived_At,
            In_Surgery_At           = src.In_Surgery_At,
            Completed_At            = src.Completed_At,
            Confirmed_At            = src.Confirmed_At,
            Cancelled_At            = src.Cancelled_At,
            Did_Not_Attend_At       = src.Did_Not_Attend_At,
            Start_Time              = src.Start_Time,
            Finish_Time             = src.Finish_Time,
            Pending_At              = src.Pending_At,
            Is_Completed            = src.Is_Completed,
            Is_Cancelled            = src.Is_Cancelled,
            Is_DNA                  = src.Is_DNA,
            Is_Arrived              = src.Is_Arrived,
            Duration_Mins           = src.Duration_Mins,
            Waiting_Mins            = src.Waiting_Mins,
            In_Surgery_Mins         = src.In_Surgery_Mins,
            DW_Updated_At           = GETDATE()
        FROM Gold.Fact_Appointments tgt
        INNER JOIN #src src ON tgt.bk_Appointment_ID = src.bk_Appointment_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_User] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Start] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Pending] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Room_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[State] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Reason] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Cancellation_Reason_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Arrived_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[In_Surgery_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Completed_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Confirmed_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Cancelled_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Did_Not_Attend_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Start_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Finish_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Pending_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Cancelled] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_DNA] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Arrived] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Waiting_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[In_Surgery_Mins] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_User] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Start] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Pending] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Room_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[State] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Reason] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Cancellation_Reason_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Arrived_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[In_Surgery_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Completed_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Confirmed_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Cancelled_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Did_Not_Attend_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Start_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Finish_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Pending_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Cancelled] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_DNA] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Arrived] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Waiting_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[In_Surgery_Mins] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Appointments (
            bk_Appointment_ID,
            fk_Patient, fk_Practitioner, fk_Payment_Plan, fk_Practice_Site, fk_User,
            fk_Date_Start, fk_Date_Pending, fk_Date_Created,
            Room_ID, State, Reason, Treatment_Description, Notes, Cancellation_Reason_ID,
            Arrived_At, In_Surgery_At, Completed_At, Confirmed_At, Cancelled_At, Did_Not_Attend_At,
            Start_Time, Finish_Time, Pending_At,
            Is_Completed, Is_Cancelled, Is_DNA, Is_Arrived,
            Duration_Mins, Waiting_Mins, In_Surgery_Mins,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.bk_Appointment_ID,
            src.fk_Patient, src.fk_Practitioner, src.fk_Payment_Plan, src.fk_Practice_Site, src.fk_User,
            src.fk_Date_Start, src.fk_Date_Pending, src.fk_Date_Created,
            src.Room_ID, src.State, src.Reason, src.Treatment_Description, src.Notes, src.Cancellation_Reason_ID,
            src.Arrived_At, src.In_Surgery_At, src.Completed_At, src.Confirmed_At, src.Cancelled_At, src.Did_Not_Attend_At,
            src.Start_Time, src.Finish_Time, src.Pending_At,
            src.Is_Completed, src.Is_Cancelled, src.Is_DNA, src.Is_Arrived,
            src.Duration_Mins, src.Waiting_Mins, src.In_Surgery_Mins,
            GETDATE(), GETDATE()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Appointments tgt WHERE tgt.bk_Appointment_ID = src.bk_Appointment_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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

CREATE OR ALTER PROCEDURE [Gold].[usp_Load_Fact_Treatment_Appointments]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       TINYINT      = 1
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
            ta.id                                                       AS bk_Treatment_Appointment_ID,
            dpat.pk_Patient                                             AS fk_Patient,
            dtp.pk_Treatment_Plan                                       AS fk_Treatment_Plan,
            dd_a.pk_Date                                                AS fk_Date_Appointment,
            dd_c.pk_Date                                                AS fk_Date_Created,
            ta.appointment_id                                           AS Appointment_ID,
            ta.treatment_plan_id                                        AS Treatment_Plan_ID,
            ta.position                                                 AS Position,
            ta.bookable                                                 AS Bookable,
            NULLIF(TRIM(ta.notes),'')                                   AS Notes,
            NULL                                                        AS Created_At,
            NULL                                                        AS Updated_At
        INTO #src
        FROM Silver.treatment_appointments ta
        LEFT JOIN Gold.Dim_Patients dpat        ON dpat.Patient_ID        = ta.patient_id
        LEFT JOIN Gold.Dim_Treatment_Plans dtp  ON dtp.Treatment_Plan_ID  = ta.treatment_plan_id
        LEFT JOIN Silver.appointments ba        ON ba.appointment_id      = ta.appointment_id
        LEFT JOIN Gold.Dim_Date dd_a            ON dd_a.Full_Date         = TRY_CAST(NULLIF(TRIM(ba.start_time),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_c            ON dd_c.Full_Date         = TRY_CAST(NULLIF(TRIM(ba.start_time),'') AS DATE)
        WHERE ta.id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Treatment_Appointments tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Treatment_Appointment_ID = tgt.bk_Treatment_Appointment_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Patient              = src.fk_Patient,
            fk_Treatment_Plan       = src.fk_Treatment_Plan,
            fk_Date_Appointment     = src.fk_Date_Appointment,
            fk_Date_Created         = src.fk_Date_Created,
            Appointment_ID          = src.Appointment_ID,
            Treatment_Plan_ID       = src.Treatment_Plan_ID,
            Position                = src.Position,
            Bookable                = src.Bookable,
            Notes                   = src.Notes,
            Updated_At              = src.Updated_At,
            DW_Updated_At           = GETDATE()
        FROM Gold.Fact_Treatment_Appointments tgt
        INNER JOIN #src src ON tgt.bk_Treatment_Appointment_ID = src.bk_Treatment_Appointment_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Appointment] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Appointment_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Position] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Bookable] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_At] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Appointment] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Appointment_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Position] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Bookable] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_At] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Treatment_Appointments (
            bk_Treatment_Appointment_ID,
            fk_Patient, fk_Treatment_Plan,
            fk_Date_Appointment, fk_Date_Created,
            Appointment_ID, Treatment_Plan_ID, Position, Bookable, Notes,
            Created_At, Updated_At, DW_Created_At, DW_Updated_At
        )
        SELECT
            src.bk_Treatment_Appointment_ID,
            src.fk_Patient, src.fk_Treatment_Plan,
            src.fk_Date_Appointment, src.fk_Date_Created,
            src.Appointment_ID, src.Treatment_Plan_ID, src.Position, src.Bookable, src.Notes,
            src.Created_At, src.Updated_At, GETDATE(), GETDATE()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Treatment_Appointments tgt WHERE tgt.bk_Treatment_Appointment_ID = src.bk_Treatment_Appointment_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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

PRINT 'Deployment complete.';
GO
