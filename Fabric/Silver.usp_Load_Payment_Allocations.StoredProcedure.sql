/****** Object:  StoredProcedure [Silver].[usp_Load_Payment_Allocations]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Payment_Allocations]
GO
CREATE PROCEDURE [Silver].[usp_Load_Payment_Allocations]
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
        ISNULL(CAST(staged.[Payment_Explanation_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Invoice_Item_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Reversal_Of_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Amount] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Description] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Transfer_From_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Transfer_From_Type] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Transfer_To_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Transfer_To_Type] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                LEFT(ID, 50)  AS [Payment_Allocation_Id],
                TRY_CAST(ROUND(CAST(Patient_ID AS float), 0) AS int)  AS [Patient_Id],
                TRY_CAST(ROUND(CAST(Payment_Explanation_ID AS float), 0) AS int)  AS [Payment_Explanation_Id],
                LEFT(Invoice_Item_ID,  50)  AS [Invoice_Item_Id],
                LEFT(Reversal_Of_ID,   50)  AS [Reversal_Of_Id],
                Amount  AS [Amount],
                LEFT(Description, 500)  AS [Description],
                LEFT(Transfer_From_ID,   50)  AS [Transfer_From_Id],
                LEFT(Transfer_From_Type, 50)  AS [Transfer_From_Type],
                LEFT(Transfer_To_ID,     50)  AS [Transfer_To_Id],
                LEFT(Transfer_To_Type,   50)  AS [Transfer_To_Type]
            FROM Bronze.Payment_Allocations
        ) AS staged;

        UPDATE tgt
        SET
            [Patient_Id] = src.[Patient_Id],
            [Payment_Explanation_Id] = src.[Payment_Explanation_Id],
            [Invoice_Item_Id] = src.[Invoice_Item_Id],
            [Reversal_Of_Id] = src.[Reversal_Of_Id],
            [Amount] = src.[Amount],
            [Description] = src.[Description],
            [Transfer_From_Id] = src.[Transfer_From_Id],
            [Transfer_From_Type] = src.[Transfer_From_Type],
            [Transfer_To_Id] = src.[Transfer_To_Id],
            [Transfer_To_Type] = src.[Transfer_To_Type],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Payment_Allocations] AS tgt
        INNER JOIN #src AS src ON tgt.[Payment_Allocation_Id] = src.[Payment_Allocation_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Payment_Allocations] ([Payment_Allocation_Id], [Patient_Id], [Payment_Explanation_Id], [Invoice_Item_Id], [Reversal_Of_Id], [Amount], [Description], [Transfer_From_Id], [Transfer_From_Type], [Transfer_To_Id], [Transfer_To_Type], [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Payment_Allocation_Id], src.[Patient_Id], src.[Payment_Explanation_Id], src.[Invoice_Item_Id], src.[Reversal_Of_Id], src.[Amount], src.[Description], src.[Transfer_From_Id], src.[Transfer_From_Type], src.[Transfer_To_Id], src.[Transfer_To_Type], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Payment_Allocations] AS tgt WHERE tgt.[Payment_Allocation_Id] = src.[Payment_Allocation_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Payment_Allocations] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Payment_Allocation_Id] = tgt.[Payment_Allocation_Id]
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