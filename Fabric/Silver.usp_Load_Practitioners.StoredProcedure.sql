/****** Object:  StoredProcedure [Silver].[usp_Load_Practitioners]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Practitioners]
GO
CREATE PROCEDURE [Silver].[usp_Load_Practitioners]
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
        ISNULL(CAST(staged.[User_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Title] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_First_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Middle_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Last_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Email] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Mobile_Phone] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Role] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Permission_Level] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_Active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_Colour] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_GDC_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_NHS_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_Default_Contract_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Contract_Targets_String] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Image_URL] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Last_Login] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Updated_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Performer_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Dentist_Type] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Practitioner_ID  AS [Practitioner_Id],
                User_ID  AS [User_Id],
                LEFT(Practitioner_Site_ID, 50)  AS [Site_Id],
                LEFT(User_Title,            50)  AS [User_Title],
                LEFT(User_First_Name,      100)  AS [User_First_Name],
                LEFT(User_Middle_Name,     100)  AS [User_Middle_Name],
                LEFT(User_Last_Name,       100)  AS [User_Last_Name],
                LEFT(User_Email,           100)  AS [User_Email],
                LEFT(User_Mobile_Phone,    100)  AS [User_Mobile_Phone],
                LEFT(User_Role,            100)  AS [User_Role],
                TRY_CAST(ROUND(CAST(User_Permission_Level AS float),0) AS int)  AS [User_Permission_Level],
                TRY_CAST(ROUND(CAST(Practitioner_Active   AS float),0) AS int)  AS [Practitioner_Active],
                LEFT(Practitioner_Colour,              100)  AS [Practitioner_Colour],
                LEFT(Practitioner_Gdc_Number,          100)  AS [Practitioner_GDC_Number],
                LEFT(Practitioner_NHS_Number,          100)  AS [Practitioner_NHS_Number],
                LEFT(Practitioner_Site_ID,             100)  AS [Practitioner_Site_Id],
                LEFT(Practitioner_Default_Contract_ID, 100)  AS [Practitioner_Default_Contract_Id],
                LEFT(Contract_Targets_String,          100)  AS [Contract_Targets_String],
                LEFT(User_Image_Url,                   100)  AS [User_Image_URL],
                LEFT(User_Last_Login,                  100)  AS [User_Last_Login],
                LEFT(User_Created_At,                  100)  AS [User_Created_At],
                LEFT(User_Updated_At,                  100)  AS [User_Updated_At],
                NULL  AS [Performer_Id],
                -- Performer_Id not in Bronze
        NULL  AS [Dentist_Type]
                -- Dentist_Type not in Bronze
            FROM Bronze.Practitioners
        ) AS staged;

        UPDATE tgt
        SET
            [User_Id] = src.[User_Id],
            [Site_Id] = src.[Site_Id],
            [User_Title] = src.[User_Title],
            [User_First_Name] = src.[User_First_Name],
            [User_Middle_Name] = src.[User_Middle_Name],
            [User_Last_Name] = src.[User_Last_Name],
            [User_Email] = src.[User_Email],
            [User_Mobile_Phone] = src.[User_Mobile_Phone],
            [User_Role] = src.[User_Role],
            [User_Permission_Level] = src.[User_Permission_Level],
            [Practitioner_Active] = src.[Practitioner_Active],
            [Practitioner_Colour] = src.[Practitioner_Colour],
            [Practitioner_GDC_Number] = src.[Practitioner_GDC_Number],
            [Practitioner_NHS_Number] = src.[Practitioner_NHS_Number],
            [Practitioner_Site_Id] = src.[Practitioner_Site_Id],
            [Practitioner_Default_Contract_Id] = src.[Practitioner_Default_Contract_Id],
            [Contract_Targets_String] = src.[Contract_Targets_String],
            [User_Image_URL] = src.[User_Image_URL],
            [User_Last_Login] = src.[User_Last_Login],
            [User_Created_At] = src.[User_Created_At],
            [User_Updated_At] = src.[User_Updated_At],
            [Performer_Id] = src.[Performer_Id],
            [Dentist_Type] = src.[Dentist_Type],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Practitioners] AS tgt
        INNER JOIN #src AS src ON tgt.[Practitioner_Id] = src.[Practitioner_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Practitioners] ([Practitioner_Id], [User_Id], [Site_Id], [User_Title], [User_First_Name], [User_Middle_Name], [User_Last_Name], [User_Email], [User_Mobile_Phone], [User_Role], [User_Permission_Level], [Practitioner_Active], [Practitioner_Colour], [Practitioner_GDC_Number], [Practitioner_NHS_Number], [Practitioner_Site_Id], [Practitioner_Default_Contract_Id], [Contract_Targets_String], [User_Image_URL], [User_Last_Login], [User_Created_At], [User_Updated_At], [Performer_Id], [Dentist_Type], [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Practitioner_Id], src.[User_Id], src.[Site_Id], src.[User_Title], src.[User_First_Name], src.[User_Middle_Name], src.[User_Last_Name], src.[User_Email], src.[User_Mobile_Phone], src.[User_Role], src.[User_Permission_Level], src.[Practitioner_Active], src.[Practitioner_Colour], src.[Practitioner_GDC_Number], src.[Practitioner_NHS_Number], src.[Practitioner_Site_Id], src.[Practitioner_Default_Contract_Id], src.[Contract_Targets_String], src.[User_Image_URL], src.[User_Last_Login], src.[User_Created_At], src.[User_Updated_At], src.[Performer_Id], src.[Dentist_Type], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Practitioners] AS tgt WHERE tgt.[Practitioner_Id] = src.[Practitioner_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Practitioners] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Practitioner_Id] = tgt.[Practitioner_Id]
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