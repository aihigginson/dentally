--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Practitioner_Diary] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Practitioner_Diary
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Practitioner_Diary @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Practitioner_Diary]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Practitioner_Diary]
GO
CREATE PROCEDURE [Silver].[usp_Load_Practitioner_Diary]
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
        ISNULL(CAST(staged.[Practitioner_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Room_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Start_Time] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Finish_Time] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Day] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Available] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(ID, 50)  AS [Id],
                Practitioner_ID  AS [Practitioner_Id],
                NULL  AS [Site_Id],
                -- Site_Id not in Bronze
        NULL  AS [Room_Id],
                -- Room_Id not in Bronze
        LEFT(Start_Time, 50)  AS [Start_Time],
                LEFT(End_Time,   50)  AS [Finish_Time],
                TRY_CAST(Day        AS date)  AS [Day],
                -- Bronze Unavailable=1 means NOT available → invert for Silver Available bit
        CASE WHEN TRY_CAST(Unavailable AS decimal(18,4)) = 1
             THEN CAST(0 AS bit) ELSE CAST(1 AS bit) END  AS [Available],
                NULL  AS [Created_At],
                NULL  AS [Updated_At]
            FROM Bronze.Practitioner_Diary
        ) AS staged;

        UPDATE tgt
        SET
            [Practitioner_Id] = src.[Practitioner_Id],
            [Site_Id] = src.[Site_Id],
            [Room_Id] = src.[Room_Id],
            [Start_Time] = src.[Start_Time],
            [Finish_Time] = src.[Finish_Time],
            [Day] = src.[Day],
            [Available] = src.[Available],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Practitioner_Diary] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Practitioner_Diary] ([Tenant_ID], [Id], [Practitioner_Id], [Site_Id], [Room_Id], [Start_Time], [Finish_Time], [Day], [Available], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Tenant_ID], src.[Id], src.[Practitioner_Id], src.[Site_Id], src.[Room_Id], src.[Start_Time], src.[Finish_Time], src.[Day], src.[Available], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Practitioner_Diary] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Practitioner_Diary] AS tgt
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
