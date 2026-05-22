--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Accounts] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Accounts
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     20/05/2026  AIH Column naming convention fixes (ID/_ID, NHS)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Accounts @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
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
        ISNULL(CAST(staged.[Patient_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Current_Balance] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Opening_Balance] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Planned_NHS_Treatment_Value] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Planned_Private_Treatment_Value] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
            Account_ID  AS [Account_ID],
                -- int → int (direct)
        Patient_ID  AS [Patient_ID],
                -- int → int (direct)
        Patient_Name  AS [Patient_Name],
            TRY_CAST(Current_Balance  AS decimal(18,4))  AS [Current_Balance],
                -- VARCHAR → decimal
        TRY_CAST(Opening_Balance  AS decimal(18,4))  AS [Opening_Balance],
            TRY_CAST(Planned_NHS_Treatment_Value   AS decimal(18,4))  AS [Planned_NHS_Treatment_Value],
            TRY_CAST(Planned_Private_Treatment_Value AS decimal(18,4))  AS [Planned_Private_Treatment_Value]
            FROM Bronze.Accounts
        ) AS staged;

        UPDATE tgt
        SET
            [Patient_ID] = src.[Patient_ID],
            [Patient_Name] = src.[Patient_Name],
            [Current_Balance] = src.[Current_Balance],
            [Opening_Balance] = src.[Opening_Balance],
            [Planned_NHS_Treatment_Value] = src.[Planned_NHS_Treatment_Value],
            [Planned_Private_Treatment_Value] = src.[Planned_Private_Treatment_Value],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Accounts] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Account_ID] = src.[Account_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Accounts] ([Tenant_ID], [Account_ID], [Patient_ID], [Patient_Name], [Current_Balance], [Opening_Balance], [Planned_NHS_Treatment_Value], [Planned_Private_Treatment_Value],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Account_ID], src.[Patient_ID], src.[Patient_Name], src.[Current_Balance], src.[Opening_Balance], src.[Planned_NHS_Treatment_Value], src.[Planned_Private_Treatment_Value],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Accounts] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Account_ID] = src.[Account_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Accounts] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Account_ID] = tgt.[Account_ID]
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
