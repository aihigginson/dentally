--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Rooms] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Rooms
--  Author           :  AIH
--  Initital Date    :  19/05/2026
--  History          :
--    *01     19/05/2026  AIH Initial Release
--    *02     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Rooms @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Rooms]    Script Date: 19/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Rooms]
GO
CREATE PROCEDURE [Silver].[usp_Load_Rooms]
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
        ISNULL(CAST(staged.[Site_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Colour] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Calendar_Position] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practice_ID] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(ID, 50)  AS [Room_ID],
                LEFT(Site_ID, 50)  AS [Site_ID],
                LEFT(Name, 255)  AS [Name],
                LEFT(Colour, 100)  AS [Colour],
                TRY_CAST(ROUND(CAST(Calendar_Position AS float), 0) AS int)  AS [Calendar_Position],
                LEFT(Created_At, 50)  AS [Created_At],
                LEFT(Updated_At, 50)  AS [Updated_At],
                LEFT(Practice_ID, 50)  AS [Practice_ID]
            FROM Bronze.Rooms
        ) AS staged;

        UPDATE tgt
        SET
            [Site_ID] = src.[Site_ID],
            [Name] = src.[Name],
            [Colour] = src.[Colour],
            [Calendar_Position] = src.[Calendar_Position],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [Practice_ID] = src.[Practice_ID],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Rooms] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Room_ID] = src.[Room_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Rooms] ([Tenant_ID], [Room_ID], [Site_ID], [Name], [Colour], [Calendar_Position], [Created_At], [Updated_At], [Practice_ID], [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Tenant_ID], src.[Room_ID], src.[Site_ID], src.[Name], src.[Colour], src.[Calendar_Position], src.[Created_At], src.[Updated_At], src.[Practice_ID], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Rooms] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Room_ID] = src.[Room_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Rooms] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Room_ID] = tgt.[Room_ID]
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
