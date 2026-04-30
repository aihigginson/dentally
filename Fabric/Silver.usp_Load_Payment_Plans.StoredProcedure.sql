--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Payment_Plans
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Payment_Plans @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Payment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Payment_Plans]
GO
CREATE PROCEDURE [Silver].[usp_Load_Payment_Plans]
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
        ISNULL(CAST(staged.[Payment_Plan_Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Active] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Colour] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Dentist_Recall_Interval] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Emergency_Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Exam_Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Exam_Scale_And_Polish_Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Hygienist_Recall_Interval] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Patient_Friendly_Name] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Scale_And_Polish_Duration] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Payment_Plan_Created_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                Payment_Plan_ID  AS [Payment_Plan_Id],
                LEFT(Payment_Plan_Site_ID, 50)  AS [Payment_Plan_Site_Id],
                CASE WHEN TRY_CAST(Payment_Plan_Active AS decimal(18,4)) = 1
             THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Payment_Plan_Active],
                LEFT(Payment_Plan_Colour, 20)  AS [Payment_Plan_Colour],
                TRY_CAST(ROUND(CAST(Dentist_Recall_Interval AS float), 0) AS int)  AS [Dentist_Recall_Interval],
                TRY_CAST(ROUND(CAST(Emergency_Duration AS float), 0) AS int)  AS [Emergency_Duration],
                TRY_CAST(ROUND(CAST(Exam_Duration AS float), 0) AS int)  AS [Exam_Duration],
                TRY_CAST(ROUND(CAST(Exam_Scale_And_Polish_Duration AS float), 0) AS int)  AS [Exam_Scale_And_Polish_Duration],
                TRY_CAST(ROUND(CAST(Hygienist_Recall_Interval AS float), 0) AS int)  AS [Hygienist_Recall_Interval],
                Payment_Plan_Name  AS [Payment_Plan_Name],
                Payment_Plan_Patient_Friendly_Name  AS [Payment_Plan_Patient_Friendly_Name],
                TRY_CAST(ROUND(CAST(Scale_And_Polish_Duration AS float), 0) AS int)  AS [Scale_And_Polish_Duration],
                TRY_CAST(Payment_Plan_Created_At AS datetime2(3))  AS [Payment_Plan_Created_At]
            FROM Bronze.Payment_Plans
        ) AS staged;

        UPDATE tgt
        SET
            [Payment_Plan_Site_Id] = src.[Payment_Plan_Site_Id],
            [Payment_Plan_Active] = src.[Payment_Plan_Active],
            [Payment_Plan_Colour] = src.[Payment_Plan_Colour],
            [Dentist_Recall_Interval] = src.[Dentist_Recall_Interval],
            [Emergency_Duration] = src.[Emergency_Duration],
            [Exam_Duration] = src.[Exam_Duration],
            [Exam_Scale_And_Polish_Duration] = src.[Exam_Scale_And_Polish_Duration],
            [Hygienist_Recall_Interval] = src.[Hygienist_Recall_Interval],
            [Payment_Plan_Name] = src.[Payment_Plan_Name],
            [Payment_Plan_Patient_Friendly_Name] = src.[Payment_Plan_Patient_Friendly_Name],
            [Scale_And_Polish_Duration] = src.[Scale_And_Polish_Duration],
            [Payment_Plan_Created_At] = src.[Payment_Plan_Created_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Payment_Plans] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Payment_Plan_Id] = src.[Payment_Plan_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Payment_Plans] ([Tenant_ID], [Payment_Plan_Id], [Payment_Plan_Site_Id], [Payment_Plan_Active], [Payment_Plan_Colour], [Dentist_Recall_Interval], [Emergency_Duration], [Exam_Duration], [Exam_Scale_And_Polish_Duration], [Hygienist_Recall_Interval], [Payment_Plan_Name], [Payment_Plan_Patient_Friendly_Name], [Scale_And_Polish_Duration], [Payment_Plan_Created_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Payment_Plan_Id], src.[Payment_Plan_Site_Id], src.[Payment_Plan_Active], src.[Payment_Plan_Colour], src.[Dentist_Recall_Interval], src.[Emergency_Duration], src.[Exam_Duration], src.[Exam_Scale_And_Polish_Duration], src.[Hygienist_Recall_Interval], src.[Payment_Plan_Name], src.[Payment_Plan_Patient_Friendly_Name], src.[Scale_And_Polish_Duration], src.[Payment_Plan_Created_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Payment_Plans] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Payment_Plan_Id] = src.[Payment_Plan_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Payment_Plans] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Payment_Plan_Id] = tgt.[Payment_Plan_Id]
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
