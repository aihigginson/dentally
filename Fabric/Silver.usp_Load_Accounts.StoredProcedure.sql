/****** Object:  StoredProcedure [Silver].[usp_Load_Accounts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Accounts]
GO
CREATE PROCEDURE [Silver].[usp_Load_Accounts]
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
        ISNULL(CAST(staged.[Patient_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Current_Balance] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Opening_Balance] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Planned_Nhs_Treatment_Value] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Planned_Private_Treatment_Value] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
            Account_ID  AS [Account_Id],
                -- int → int (direct)
        Patient_ID  AS [Patient_Id],
                -- int → int (direct)
        Patient_Name  AS [Patient_Name],
            TRY_CAST(Current_Balance  AS decimal(18,4))  AS [Current_Balance],
                -- VARCHAR → decimal
        TRY_CAST(Opening_Balance  AS decimal(18,4))  AS [Opening_Balance],
            TRY_CAST(Planned_NHS_Treatment_Value   AS decimal(18,4))  AS [Planned_Nhs_Treatment_Value],
            TRY_CAST(Planned_Private_Treatment_Value AS decimal(18,4))  AS [Planned_Private_Treatment_Value]
            FROM Bronze.Accounts
        ) AS staged;

        UPDATE tgt
        SET
            [Patient_Id] = src.[Patient_Id],
            [Patient_Name] = src.[Patient_Name],
            [Current_Balance] = src.[Current_Balance],
            [Opening_Balance] = src.[Opening_Balance],
            [Planned_Nhs_Treatment_Value] = src.[Planned_Nhs_Treatment_Value],
            [Planned_Private_Treatment_Value] = src.[Planned_Private_Treatment_Value],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Accounts] AS tgt
        INNER JOIN #src AS src ON tgt.[Account_Id] = src.[Account_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Accounts] ([Account_Id], [Patient_Id], [Patient_Name], [Current_Balance], [Opening_Balance], [Planned_Nhs_Treatment_Value], [Planned_Private_Treatment_Value],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Account_Id], src.[Patient_Id], src.[Patient_Name], src.[Current_Balance], src.[Opening_Balance], src.[Planned_Nhs_Treatment_Value], src.[Planned_Private_Treatment_Value],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Accounts] AS tgt WHERE tgt.[Account_Id] = src.[Account_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Accounts] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Account_Id] = tgt.[Account_Id]
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
