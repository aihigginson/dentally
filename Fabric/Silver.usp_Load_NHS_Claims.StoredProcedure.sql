--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_NHS_Claims] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_NHS_Claims
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Load_NHS_Claims @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_NHS_Claims]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_NHS_Claims]
GO
CREATE PROCEDURE [Silver].[usp_Load_NHS_Claims]
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
        ISNULL(CAST(staged.[Nhs_Claim_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_Plan_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Contract_Id] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Claim_Status] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Sequence_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Uda_Band] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Expected_Uda] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Awarded_Uda] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Charge] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Dentist_Charge] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Awarded_Dentist_Charge] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Ni_Calculated_Dentist_Fee] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Ni_Calculated_Patient_Fee] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Scot_Amount_Authorised] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Scot_Amount_Expected] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Ortho] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Continuation_Part_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Status_Comments] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Approval_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Submitted_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Nhs_Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(ID, 50)  AS [Nhs_Claim_Id],
                -- Bronze Patient_ID is decimal(18,4); Silver is int
        TRY_CAST(ROUND(CAST(Patient_ID AS float), 0) AS int)  AS [Patient_Id],
                Practitioner_ID  AS [Practitioner_Id],
                -- Bronze Treatment_Plan_ID is decimal(18,4); Silver is int
        TRY_CAST(ROUND(CAST(Treatment_Plan_ID AS float), 0) AS int)  AS [Treatment_Plan_Id],
                LEFT(Site_ID, 50)  AS [Site_Id],
                LEFT(Contract_ID, 50)  AS [Contract_Id],
                LEFT(Claim_Status, 50)  AS [Claim_Status],
                -- Bronze Sequence_Number is decimal(18,4); Silver is int
        TRY_CAST(ROUND(CAST(Sequence_Number AS float), 0) AS int)  AS [Sequence_Number],
                -- Bronze UDA_Band is decimal(18,4); Silver is VARCHAR(10)
        LEFT(CAST(CAST(UDA_Band AS int) AS VARCHAR(10)), 10)  AS [Uda_Band],
                Expected_UDA  AS [Expected_Uda],
                Awarded_UDA  AS [Awarded_Uda],
                Patient_Charge  AS [Patient_Charge],
                NULL  AS [Dentist_Charge],
                -- Dentist_Charge not in Bronze
        NULL  AS [Awarded_Dentist_Charge],
                -- Awarded_Dentist_Charge not in Bronze
        NULL  AS [Ni_Calculated_Dentist_Fee],
                -- NI_Calculated_Dentist_Fee not in Bronze
        NULL  AS [Ni_Calculated_Patient_Fee],
                -- NI_Calculated_Patient_Fee not in Bronze
        Scot_Amount_Authorised  AS [Scot_Amount_Authorised],
                Scot_Amount_Expected  AS [Scot_Amount_Expected],
                -- Bronze Ortho is decimal(18,4); Silver is bit
        CASE WHEN Ortho = 1 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Ortho],
                -- Bronze Continuation_Part_Number is VARCHAR(255); Silver is int
        TRY_CAST(Continuation_Part_Number AS int)  AS [Continuation_Part_Number],
                Status_Comments  AS [Status_Comments],
                TRY_CAST(Approval_Date   AS date)  AS [Approval_Date],
                TRY_CAST(Submitted_Date  AS date)  AS [Submitted_Date],
                CAST(NULL AS datetime2(3))  AS [Nhs_Updated_At]
                -- Nhs_Updated_At not in Bronze
            FROM Bronze.NHS_Claims
        ) AS staged;

        UPDATE tgt
        SET
            [Patient_Id] = src.[Patient_Id],
            [Practitioner_Id] = src.[Practitioner_Id],
            [Treatment_Plan_Id] = src.[Treatment_Plan_Id],
            [Site_Id] = src.[Site_Id],
            [Contract_Id] = src.[Contract_Id],
            [Claim_Status] = src.[Claim_Status],
            [Sequence_Number] = src.[Sequence_Number],
            [Uda_Band] = src.[Uda_Band],
            [Expected_Uda] = src.[Expected_Uda],
            [Awarded_Uda] = src.[Awarded_Uda],
            [Patient_Charge] = src.[Patient_Charge],
            [Dentist_Charge] = src.[Dentist_Charge],
            [Awarded_Dentist_Charge] = src.[Awarded_Dentist_Charge],
            [Ni_Calculated_Dentist_Fee] = src.[Ni_Calculated_Dentist_Fee],
            [Ni_Calculated_Patient_Fee] = src.[Ni_Calculated_Patient_Fee],
            [Scot_Amount_Authorised] = src.[Scot_Amount_Authorised],
            [Scot_Amount_Expected] = src.[Scot_Amount_Expected],
            [Ortho] = src.[Ortho],
            [Continuation_Part_Number] = src.[Continuation_Part_Number],
            [Status_Comments] = src.[Status_Comments],
            [Approval_Date] = src.[Approval_Date],
            [Submitted_Date] = src.[Submitted_Date],
            [Nhs_Updated_At] = src.[Nhs_Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[NHS_Claims] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Nhs_Claim_Id] = src.[Nhs_Claim_Id]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[NHS_Claims] ([Tenant_ID], [Nhs_Claim_Id], [Patient_Id], [Practitioner_Id], [Treatment_Plan_Id], [Site_Id], [Contract_Id], [Claim_Status], [Sequence_Number], [Uda_Band], [Expected_Uda], [Awarded_Uda], [Patient_Charge], [Dentist_Charge], [Awarded_Dentist_Charge], [Ni_Calculated_Dentist_Fee], [Ni_Calculated_Patient_Fee], [Scot_Amount_Authorised], [Scot_Amount_Expected], [Ortho], [Continuation_Part_Number], [Status_Comments], [Approval_Date], [Submitted_Date], [Nhs_Updated_At], [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[Nhs_Claim_Id], src.[Patient_Id], src.[Practitioner_Id], src.[Treatment_Plan_Id], src.[Site_Id], src.[Contract_Id], src.[Claim_Status], src.[Sequence_Number], src.[Uda_Band], src.[Expected_Uda], src.[Awarded_Uda], src.[Patient_Charge], src.[Dentist_Charge], src.[Awarded_Dentist_Charge], src.[Ni_Calculated_Dentist_Fee], src.[Ni_Calculated_Patient_Fee], src.[Scot_Amount_Authorised], src.[Scot_Amount_Expected], src.[Ortho], src.[Continuation_Part_Number], src.[Status_Comments], src.[Approval_Date], src.[Submitted_Date], src.[Nhs_Updated_At], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[NHS_Claims] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Nhs_Claim_Id] = src.[Nhs_Claim_Id]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[NHS_Claims] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Nhs_Claim_Id] = tgt.[Nhs_Claim_Id]
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