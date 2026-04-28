/****** Object:  StoredProcedure [Silver].[usp_Load_Practitioner_Diary_Breaks]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Practitioner_Diary_Breaks]
GO
CREATE PROCEDURE [Silver].[usp_Load_Practitioner_Diary_Breaks]
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
        ISNULL(CAST(staged.[Break_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[End_Time] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                LEFT(Practitioner_Diary_ID, 255)  AS [Practitioner_Diary_ID],
                LEFT(Break_Name,            255)  AS [Break_Name],
                LEFT(Start_Time,            255)  AS [Start_Time],
                LEFT(End_Time,              255)  AS [End_Time]
            FROM Bronze.Practitioner_Diary_Breaks
            WHERE Practitioner_Diary_ID IS NOT NULL
              AND Start_Time IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Break_Name] = src.[Break_Name],
            [End_Time] = src.[End_Time],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Practitioner_Diary_Breaks] AS tgt
        INNER JOIN #src AS src
            ON tgt.[Practitioner_Diary_ID] = src.[Practitioner_Diary_ID]
           AND tgt.[Start_Time]            = src.[Start_Time]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Practitioner_Diary_Breaks] ([Practitioner_Diary_ID], [Break_Name], [Start_Time], [End_Time],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Practitioner_Diary_ID], src.[Break_Name], src.[Start_Time], src.[End_Time],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Practitioner_Diary_Breaks] AS tgt
            WHERE tgt.[Practitioner_Diary_ID] = src.[Practitioner_Diary_ID]
              AND tgt.[Start_Time]            = src.[Start_Time]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Practitioner_Diary_Breaks] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src
            WHERE src.[Practitioner_Diary_ID] = tgt.[Practitioner_Diary_ID]
              AND src.[Start_Time]            = tgt.[Start_Time]
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
