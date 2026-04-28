/****** Object:  StoredProcedure [Silver].[usp_Load_Treatment_Categories]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Treatment_Categories]
GO
CREATE PROCEDURE [Silver].[usp_Load_Treatment_Categories]
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
        ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Description] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Colour] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Position] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                LEFT(CAST(TRY_CAST(ROUND(CAST(ID AS float),0) AS bigint) AS VARCHAR(50)), 50)  AS [Id],
                Name  AS [Name],
                NULL  AS [Description],
                -- Description not in Bronze
        NULL  AS [Colour],
                -- Colour not in Bronze
        NULL  AS [Position],
                -- Position not in Bronze
        CAST(NULL AS bit)  AS [Active],
                -- Active not in Bronze
        NULL  AS [Created_At],
                NULL  AS [Updated_At]
            FROM Bronze.Treatment_Categories
            WHERE ID IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Name] = src.[Name],
            [Description] = src.[Description],
            [Colour] = src.[Colour],
            [Position] = src.[Position],
            [Active] = src.[Active],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Treatment_Categories] AS tgt
        INNER JOIN #src AS src ON tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Treatment_Categories] ([Id], [Name], [Description], [Colour], [Position], [Active], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Id], src.[Name], src.[Description], src.[Colour], src.[Position], src.[Active], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Treatment_Categories] AS tgt WHERE tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Treatment_Categories] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Id] = tgt.[Id]
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
