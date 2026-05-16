--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Payment_Explanations] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Payment_Explanations
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Payment_Explanations @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Payment_Explanations]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Payment_Explanations]
GO
CREATE PROCEDURE [Silver].[usp_Load_Payment_Explanations]
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
        ISNULL(CAST(staged.[Payment_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Invoice_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[User_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Reference] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Invoice_Reference] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Amount] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Comments] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                -- Bronze ID is varchar(255); Silver is int
        TRY_CAST(ID AS int)  AS [Explanation_Id],
                Payment_ID  AS [Payment_Id],
                Invoice_ID  AS [Invoice_Id],
                User_ID  AS [User_Id],
                LEFT(Payment_Reference, 50)  AS [Payment_Reference],
                LEFT(Invoice_Reference, 50)  AS [Invoice_Reference],
                Amount  AS [Amount],
                Comments  AS [Comments]
            FROM Bronze.Payment_Explanations
            WHERE TRY_CAST(ID AS int) IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Payment_Id] = src.[Payment_Id],
            [Invoice_Id] = src.[Invoice_Id],
            [User_Id] = src.[User_Id],
            [Payment_Reference] = src.[Payment_Reference],
            [Invoice_Reference] = src.[Invoice_Reference],
            [Amount] = src.[Amount],
            [Comments] = src.[Comments],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Payment_Explanations] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Explanation_Id] = src.[Explanation_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Payment_Explanations] ([Tenant_ID], [Explanation_Id], [Payment_Id], [Invoice_Id], [User_Id], [Payment_Reference], [Invoice_Reference], [Amount], [Comments],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Explanation_Id], src.[Payment_Id], src.[Invoice_Id], src.[User_Id], src.[Payment_Reference], src.[Invoice_Reference], src.[Amount], src.[Comments],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Payment_Explanations] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Explanation_Id] = src.[Explanation_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Payment_Explanations] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Explanation_Id] = tgt.[Explanation_Id]
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
