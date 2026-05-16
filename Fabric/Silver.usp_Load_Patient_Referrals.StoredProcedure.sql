--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Patient_Referrals] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Patient_Referrals
--  Author           :  AIH
--  Initital Date    :  15/05/2026
--  History          :
--    *01     15/05/2026  AIH Initial Release
--  To Run           :   DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Silver.usp_Load_Patient_Referrals @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Patient_Referrals]    Script Date: 15/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Patient_Referrals]
GO
CREATE PROCEDURE [Silver].[usp_Load_Patient_Referrals]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       smallint         = 1
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
            ISNULL(CAST(staged.[Patient_Id]      AS VARCHAR(500)), ''),
            ISNULL(CAST(staged.[Site_Id]         AS VARCHAR(500)), ''),
            ISNULL(CAST(staged.[Reference]       AS VARCHAR(500)), ''),
            ISNULL(CAST(staged.[Status]          AS VARCHAR(500)), ''),
            ISNULL(CAST(staged.[Referrable_Type] AS VARCHAR(500)), '')
            ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID                                                                       AS [Tenant_ID],
                TRY_CAST(ROUND(CAST(Patient_ID AS float), 0) AS int)                           AS [Patient_Id],
                LEFT(Site_ID, 50)                                                               AS [Site_Id],
                TRY_CAST(ROUND(CAST(User_ID AS float), 0) AS int)                              AS [User_Id],
                LEFT(Reference, 50)                                                             AS [Reference],
                LEFT(Status, 50)                                                                AS [Status],
                LEFT(Referrable_Type, 100)                                                      AS [Referrable_Type],
                LEFT(Services_Appointment_ID, 50)                                               AS [Services_Appointment_Id],
                CAST(Additional_Information AS VARCHAR(MAX))                                    AS [Additional_Information],
                CASE WHEN LOWER(TRIM(Consented_By_Patient)) IN ('1','true') THEN 1 ELSE 0 END  AS [Consented_By_Patient],
                TRY_CAST(ROUND(CAST(Referred_Practitioner_ID AS float), 0) AS int)             AS [Referred_Practitioner_Id],
                LEFT(Referred_Site_ID, 50)                                                      AS [Referred_Site_Id],
                TRY_CAST(LEFT(NULLIF(TRIM(Created_At), ''), 23) AS datetime2(3))               AS [Created_At],
                ID                                                                              AS [Patient_Referral_Id]
            FROM Bronze.Patient_Referrals
        ) AS staged;

        UPDATE tgt
        SET
            [Patient_Id]              = src.[Patient_Id],
            [Site_Id]                 = src.[Site_Id],
            [User_Id]                 = src.[User_Id],
            [Reference]               = src.[Reference],
            [Status]                  = src.[Status],
            [Referrable_Type]         = src.[Referrable_Type],
            [Services_Appointment_Id] = src.[Services_Appointment_Id],
            [Additional_Information]  = src.[Additional_Information],
            [Consented_By_Patient]    = src.[Consented_By_Patient],
            [Referred_Practitioner_Id]= src.[Referred_Practitioner_Id],
            [Referred_Site_Id]        = src.[Referred_Site_Id],
            [Created_At]              = src.[Created_At],
            [DW_Updated_At]           = SYSUTCDATETIME(),
            [_Row_Hash]               = src._Hash
        FROM [Silver].[Patient_Referrals] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Patient_Referral_Id] = src.[Patient_Referral_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Patient_Referrals] (
            [Tenant_ID], [Patient_Referral_Id], [Patient_Id], [Site_Id], [User_Id],
            [Reference], [Status], [Referrable_Type], [Services_Appointment_Id],
            [Additional_Information], [Consented_By_Patient],
            [Referred_Practitioner_Id], [Referred_Site_Id], [Created_At],
            [DW_Created_At], [DW_Updated_At], [_Row_Hash]
        )
        SELECT
            src.[Tenant_ID], src.[Patient_Referral_Id], src.[Patient_Id], src.[Site_Id], src.[User_Id],
            src.[Reference], src.[Status], src.[Referrable_Type], src.[Services_Appointment_Id],
            src.[Additional_Information], src.[Consented_By_Patient],
            src.[Referred_Practitioner_Id], src.[Referred_Site_Id], src.[Created_At],
            SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Patient_Referrals] AS tgt
            WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Patient_Referral_Id] = src.[Patient_Referral_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Patient_Referrals] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src
            WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Patient_Referral_Id] = tgt.[Patient_Referral_Id]
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
