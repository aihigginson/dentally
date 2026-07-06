--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Patient_Referral_Reasons] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Patient_Referral_Reasons
--  Author           :  AIH
--  Initital Date    :  19/05/2026
--  History          :
--    *01     19/05/2026  AIH Initial Release
--    *02     20/05/2026  AIH Column naming convention fixes (ID/_ID); fix CONCAT_WS single-column hash
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_Patient_Referral_Reasons @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Patient_Referral_Reasons]    Script Date: 19/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Patient_Referral_Reasons]
GO
CREATE PROCEDURE [Silver].[usp_Load_Patient_Referral_Reasons]
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
            CONVERT(VARBINARY(32), HASHBYTES('SHA2_256', ISNULL(CAST(staged.[Name] AS VARCHAR(500)), ''))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                -- Bronze Patient_Referral_ID is decimal(18,4); Silver is int
                TRY_CAST(ROUND(TRY_CAST(Patient_Referral_ID AS float), 0) AS int)  AS [Patient_Referral_ID],
                LEFT(Referral_Reason_ID, 50)  AS [Referral_Reason_ID],
                LEFT(Name, 255)  AS [Name]
            FROM Bronze.Patient_Referral_Reasons
            WHERE TRY_CAST(ROUND(TRY_CAST(Patient_Referral_ID AS float), 0) AS int) IS NOT NULL
        ) AS staged;

        UPDATE tgt
        SET
            [Name] = src.[Name],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Patient_Referral_Reasons] AS tgt
        INNER JOIN #src AS src
            ON tgt.[Tenant_ID]          = src.[Tenant_ID]
           AND tgt.[Patient_Referral_ID] = src.[Patient_Referral_ID]
           AND tgt.[Referral_Reason_ID]  = src.[Referral_Reason_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Patient_Referral_Reasons] ([Tenant_ID], [Patient_Referral_ID], [Referral_Reason_ID], [Name], [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Patient_Referral_ID], src.[Referral_Reason_ID], src.[Name], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Patient_Referral_Reasons] AS tgt
            WHERE tgt.[Tenant_ID]          = src.[Tenant_ID]
              AND tgt.[Patient_Referral_ID] = src.[Patient_Referral_ID]
              AND tgt.[Referral_Reason_ID]  = src.[Referral_Reason_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Patient_Referral_Reasons] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src
            WHERE src.[Tenant_ID]          = tgt.[Tenant_ID]
              AND src.[Patient_Referral_ID] = tgt.[Patient_Referral_ID]
              AND src.[Referral_Reason_ID]  = tgt.[Referral_Reason_ID]
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
