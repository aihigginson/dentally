--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Fees
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     30/04/2026  AIH Fee_Id changed from uniqueidentifier to VARCHAR(255) — mock IDs are not UUIDs
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Fees @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Fees]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Fees]
GO
CREATE PROCEDURE [Silver].[usp_Load_Fees]
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
        ISNULL(CAST(staged.[Treatment_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Price] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(Fee_ID, 255)                      AS [Fee_Id],
                -- Bronze Treatment_ID is decimal(18,4); Silver is int
        TRY_CAST(ROUND(CAST(Treatment_ID AS float), 0) AS int)  AS [Treatment_Id],
                Payment_Plan_ID  AS [Payment_Plan_Id],
                TRY_CAST(Price_One       AS decimal(18,4))  AS [Price]
            FROM Bronze.Fees
        ) AS staged;

        UPDATE tgt
        SET
            [Treatment_Id] = src.[Treatment_Id],
            [Payment_Plan_Id] = src.[Payment_Plan_Id],
            [Price] = src.[Price],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Fees] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Fee_Id] = src.[Fee_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Fees] ([Tenant_ID], [Fee_Id], [Treatment_Id], [Payment_Plan_Id], [Price], [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Fee_Id], src.[Treatment_Id], src.[Payment_Plan_Id], src.[Price], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Fees] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Fee_Id] = src.[Fee_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Fees] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Fee_Id] = tgt.[Fee_Id]
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