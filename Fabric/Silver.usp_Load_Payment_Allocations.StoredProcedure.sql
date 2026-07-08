--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Payment_Allocations] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Payment_Allocations
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Payment_Allocations @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
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
        ISNULL(CAST(staged.[Patient_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Explanation_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Invoice_Item_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Reversal_Of_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Amount] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Description] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Transfer_From_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Transfer_From_Type] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Transfer_To_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Transfer_To_Type] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(ID, 50)  AS [Payment_Allocation_ID],
                TRY_CAST(ROUND(TRY_CAST(Patient_ID AS float), 0) AS int)  AS [Patient_ID],
                TRY_CAST(ROUND(TRY_CAST(Payment_Explanation_ID AS float), 0) AS int)  AS [Payment_Explanation_ID],
                LEFT(Invoice_Item_ID,  50)  AS [Invoice_Item_ID],
                LEFT(Reversal_Of_ID,   50)  AS [Reversal_Of_ID],
                Amount  AS [Amount],
                LEFT(Description, 500)  AS [Description],
                LEFT(Transfer_From_ID,   50)  AS [Transfer_From_ID],
                LEFT(Transfer_From_Type, 50)  AS [Transfer_From_Type],
                LEFT(Transfer_To_ID,     50)  AS [Transfer_To_ID],
                LEFT(Transfer_To_Type,   50)  AS [Transfer_To_Type]
            FROM Bronze.Payment_Allocations
        ) AS staged;

        UPDATE tgt
        SET
            [Patient_ID] = src.[Patient_ID],
            [Payment_Explanation_ID] = src.[Payment_Explanation_ID],
            [Invoice_Item_ID] = src.[Invoice_Item_ID],
            [Reversal_Of_ID] = src.[Reversal_Of_ID],
            [Amount] = src.[Amount],
            [Description] = src.[Description],
            [Transfer_From_ID] = src.[Transfer_From_ID],
            [Transfer_From_Type] = src.[Transfer_From_Type],
            [Transfer_To_ID] = src.[Transfer_To_ID],
            [Transfer_To_Type] = src.[Transfer_To_Type],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Payment_Allocations] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Payment_Allocation_ID] = src.[Payment_Allocation_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Payment_Allocations] ([Tenant_ID], [Payment_Allocation_ID], [Patient_ID], [Payment_Explanation_ID], [Invoice_Item_ID], [Reversal_Of_ID], [Amount], [Description], [Transfer_From_ID], [Transfer_From_Type], [Transfer_To_ID], [Transfer_To_Type], [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Tenant_ID], src.[Payment_Allocation_ID], src.[Patient_ID], src.[Payment_Explanation_ID], src.[Invoice_Item_ID], src.[Reversal_Of_ID], src.[Amount], src.[Description], src.[Transfer_From_ID], src.[Transfer_From_Type], src.[Transfer_To_ID], src.[Transfer_To_Type], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Payment_Allocations] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Payment_Allocation_ID] = src.[Payment_Allocation_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Payment_Allocations] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Payment_Allocation_ID] = tgt.[Payment_Allocation_ID]
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