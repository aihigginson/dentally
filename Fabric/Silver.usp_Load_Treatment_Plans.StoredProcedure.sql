--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Treatment_Plans] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Treatment_Plans
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     20/05/2026  AIH Column naming convention fixes (ID/_ID, NHS, Private_treatment_value -> Private_Treatment_Value)
--    *03     02/06/2026  AIH Bronze boolean columns are now VARCHAR; convert with LOWER(TRIM) IN ('true','1')
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Treatment_Plans @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Treatment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Treatment_Plans]
GO
CREATE PROCEDURE [Silver].[usp_Load_Treatment_Plans]
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
        ISNULL(CAST(staged.[Nickname] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Completed] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS_Course_Part] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Accepted_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Completed_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Last_Completed_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS_UDA_Value] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS_Completed_UDA_Value] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Private_Treatment_Value] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Start_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[End_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Created_At] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                TRY_CAST(ROUND(TRY_CAST(ID AS float),0) AS int)  AS [Id],
                LEFT(Nickname, 50)  AS [Nickname],
                TRY_CAST(ROUND(TRY_CAST(Patient_ID AS float),0) AS int)  AS [Patient_ID],
                Practitioner_ID  AS [Practitioner_ID],
                NULL  AS [Site_ID],
                -- Site_ID not in Bronze
        CASE WHEN LOWER(TRIM(Completed)) IN ('true','1') THEN 1 ELSE 0 END  AS [Completed],
                NULL  AS [NHS_Course_Part],
                -- NHS_Course_Part not in Bronze
        NULL  AS [Accepted_At],
                -- Accepted_At not in Bronze
        LEFT(Completed_At,       50)  AS [Completed_At],
                LEFT(Last_Completed_At,  50)  AS [Last_Completed_At],
                LEFT(CAST(NHS_UDA_Value AS VARCHAR(50)), 50)  AS [NHS_UDA_Value],
                LEFT(CAST(NHS_Completed_UDA_Value AS VARCHAR(50)), 50)  AS [NHS_Completed_UDA_Value],
                LEFT(CAST(Private_Treatment_Value AS VARCHAR(50)), 50)  AS [Private_Treatment_Value],
                LEFT(Start_Date, 50)  AS [Start_Date],
                LEFT(End_Date,   50)  AS [End_Date],
                LEFT(Created_At, 50)  AS [Created_At],
                LEFT(Updated_At, 50)  AS [Updated_At]
            FROM Bronze.Treatment_Plans
            WHERE TRY_CAST(ROUND(TRY_CAST(ID AS float),0) AS int) IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Nickname] = src.[Nickname],
            [Patient_ID] = src.[Patient_ID],
            [Practitioner_ID] = src.[Practitioner_ID],
            [Site_ID] = src.[Site_ID],
            [Completed] = src.[Completed],
            [NHS_Course_Part] = src.[NHS_Course_Part],
            [Accepted_At] = src.[Accepted_At],
            [Completed_At] = src.[Completed_At],
            [Last_Completed_At] = src.[Last_Completed_At],
            [NHS_UDA_Value] = src.[NHS_UDA_Value],
            [NHS_Completed_UDA_Value] = src.[NHS_Completed_UDA_Value],
            [Private_Treatment_Value] = src.[Private_Treatment_Value],
            [Start_Date] = src.[Start_Date],
            [End_Date] = src.[End_Date],
            [Created_At] = src.[Created_At],
            [Updated_At] = src.[Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Treatment_Plans] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Treatment_Plans] ([Tenant_ID], [Id], [Nickname], [Patient_ID], [Practitioner_ID], [Site_ID], [Completed], [NHS_Course_Part], [Accepted_At], [Completed_At], [Last_Completed_At], [NHS_UDA_Value], [NHS_Completed_UDA_Value], [Private_Treatment_Value], [Start_Date], [End_Date], [Created_At], [Updated_At],
                [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Id], src.[Nickname], src.[Patient_ID], src.[Practitioner_ID], src.[Site_ID], src.[Completed], src.[NHS_Course_Part], src.[Accepted_At], src.[Completed_At], src.[Last_Completed_At], src.[NHS_UDA_Value], src.[NHS_Completed_UDA_Value], src.[Private_Treatment_Value], src.[Start_Date], src.[End_Date], src.[Created_At], src.[Updated_At],
                SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Treatment_Plans] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Id] = src.[Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Treatment_Plans] AS tgt
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
