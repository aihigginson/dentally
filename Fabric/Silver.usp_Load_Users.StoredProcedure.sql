--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Users
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Users @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Users]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Users]
GO
CREATE PROCEDURE [Silver].[usp_Load_Users]
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
        ISNULL(CAST(staged.[Email] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Title] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[First_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Middle_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Last_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Mobile_Phone] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Role] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Permission_Level] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practice_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Image_URL] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Last_Login] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                TRY_CAST(ROUND(CAST(ID AS float),0) AS int)  AS [Id],
                Email  AS [Email],
                NULL  AS [Title],
                -- Title not in Bronze.Users
        LEFT(First_Name,  100)  AS [First_Name],
                LEFT(Middle_Name, 100)  AS [Middle_Name],
                LEFT(Last_Name,   100)  AS [Last_Name],
                LEFT(Mobile_Phone,100)  AS [Mobile_Phone],
                LEFT(Role,        100)  AS [Role],
                TRY_CAST(ROUND(CAST(Permission_Level AS float),0) AS int)  AS [Permission_Level],
                LEFT(Practice_ID, 100)  AS [Practice_Id],
                LEFT(Site_ID,     100)  AS [Site_Id],
                LEFT(Image_Url,   100)  AS [Image_URL],
                LEFT(Last_Login,  100)  AS [Last_Login],
                LEFT(Created_At,  100)  AS [Created_At],
                LEFT(Updated_At,  100)  AS [Updated_At]
            FROM Bronze.Users
            WHERE TRY_CAST(ROUND(CAST(ID AS float),0) AS int) IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Email] = src.[Email],
            [Title] = src.[Title],
            [First_Name] = src.[First_Name],
            [Middle_Name] = src.[Middle_Name],
            [Last_Name] = src.[Last_Name],
            [Mobile_Phone] = src.[Mobile_Phone],
            [Role] = src.[Role],
            [Permission_Level] = src.[Permission_Level],
            [Practice_Id] = src.[Practice_Id],
            [Site_Id] = src.[Site_Id],
            [Image_URL] = src.[Image_URL],
            [Last_Login] = src.[Last_Login],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Users] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Users] ([Tenant_ID], [Id], [Email], [Title], [First_Name], [Middle_Name], [Last_Name], [Mobile_Phone], [Role], [Permission_Level], [Practice_Id], [Site_Id], [Image_URL], [Last_Login], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Id], src.[Email], src.[Title], src.[First_Name], src.[Middle_Name], src.[Last_Name], src.[Mobile_Phone], src.[Role], src.[Permission_Level], src.[Practice_Id], src.[Site_Id], src.[Image_URL], src.[Last_Login], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Users] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Users] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Id] = tgt.[Id]
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
