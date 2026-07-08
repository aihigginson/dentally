--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Patient_Stats] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Patient_Stats
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     20/05/2026  AIH Column naming convention fixes (Patient_Id -> Patient_ID, Last_Fta -> Last_FTA, Nhs -> NHS)
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Patient_Stats @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Patient_Stats]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Patient_Stats]
GO
CREATE PROCEDURE [Silver].[usp_Load_Patient_Stats]
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
        ISNULL(CAST(staged.[First_Appointment_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[First_Exam_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Last_Appointment_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Last_Exam_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Last_Scale_And_Polish_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Last_FTA_Appointment_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Last_Cancelled_Appointment_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Next_Appointment_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Next_Exam_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Next_Scale_And_Polish_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Total_Paid] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Total_Invoiced] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS_Exemption_Code] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                -- Bronze Patient_ID is decimal(18,4); Silver is int
        TRY_CAST(ROUND(TRY_CAST(Patient_ID AS float), 0) AS int)  AS [Patient_ID],
                LEFT(First_Appointment_Date,            50)  AS [First_Appointment_Date],
                LEFT(First_Exam_Date,                   50)  AS [First_Exam_Date],
                LEFT(Last_Appointment_Date,             50)  AS [Last_Appointment_Date],
                LEFT(Last_Exam_Date,                    50)  AS [Last_Exam_Date],
                LEFT(Last_Scale_And_Polish_Date,        50)  AS [Last_Scale_And_Polish_Date],
                LEFT(Last_FTA_Appointment_Date,         50)  AS [Last_FTA_Appointment_Date],
                LEFT(Last_Cancelled_Appointment_Date,   50)  AS [Last_Cancelled_Appointment_Date],
                LEFT(Next_Appointment_Date,             50)  AS [Next_Appointment_Date],
                LEFT(Next_Exam_Date,                    50)  AS [Next_Exam_Date],
                LEFT(Next_Scale_And_Polish_Date,        50)  AS [Next_Scale_And_Polish_Date],
                Total_Paid  AS [Total_Paid],
                Total_Invoiced  AS [Total_Invoiced],
                -- Bronze NHS_Exemption_Code is decimal(18,4); Silver is VARCHAR(20)
        LEFT(CAST(CAST(NHS_Exemption_Code AS int) AS VARCHAR(20)), 20)  AS [NHS_Exemption_Code],
                LEFT(Created_At, 50)  AS [Created_At],
                LEFT(Updated_At, 50)  AS [Updated_At]
            FROM Bronze.Patient_Stats
            WHERE TRY_CAST(ROUND(TRY_CAST(Patient_ID AS float), 0) AS int) IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [First_Appointment_Date] = src.[First_Appointment_Date],
            [First_Exam_Date] = src.[First_Exam_Date],
            [Last_Appointment_Date] = src.[Last_Appointment_Date],
            [Last_Exam_Date] = src.[Last_Exam_Date],
            [Last_Scale_And_Polish_Date] = src.[Last_Scale_And_Polish_Date],
            [Last_FTA_Appointment_Date] = src.[Last_FTA_Appointment_Date],
            [Last_Cancelled_Appointment_Date] = src.[Last_Cancelled_Appointment_Date],
            [Next_Appointment_Date] = src.[Next_Appointment_Date],
            [Next_Exam_Date] = src.[Next_Exam_Date],
            [Next_Scale_And_Polish_Date] = src.[Next_Scale_And_Polish_Date],
            [Total_Paid] = src.[Total_Paid],
            [Total_Invoiced] = src.[Total_Invoiced],
            [NHS_Exemption_Code] = src.[NHS_Exemption_Code],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash,
            [_Raw_Json]     = NULL
        FROM [Silver].[Patient_Stats] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Patient_ID] = src.[Patient_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Patient_Stats] ([Tenant_ID], [Patient_ID], [First_Appointment_Date], [First_Exam_Date], [Last_Appointment_Date], [Last_Exam_Date], [Last_Scale_And_Polish_Date], [Last_FTA_Appointment_Date], [Last_Cancelled_Appointment_Date], [Next_Appointment_Date], [Next_Exam_Date], [Next_Scale_And_Polish_Date], [Total_Paid], [Total_Invoiced], [NHS_Exemption_Code], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash], [_Raw_Json])
        SELECT src.[Tenant_ID], src.[Patient_ID], src.[First_Appointment_Date], src.[First_Exam_Date], src.[Last_Appointment_Date], src.[Last_Exam_Date], src.[Last_Scale_And_Polish_Date], src.[Last_FTA_Appointment_Date], src.[Last_Cancelled_Appointment_Date], src.[Next_Appointment_Date], src.[Next_Exam_Date], src.[Next_Scale_And_Polish_Date], src.[Total_Paid], src.[Total_Invoiced], src.[NHS_Exemption_Code], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash, NULL
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Patient_Stats] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Patient_ID] = src.[Patient_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Patient_Stats] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Patient_ID] = tgt.[Patient_ID]
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
