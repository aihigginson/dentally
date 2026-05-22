--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_NHS_Claims] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_NHS_Claims
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     19/05/2026  AIH Read Dentist_Charge, Awarded_Dentist_Charge, NI_Calculated_Dentist_Fee, NI_Calculated_Patient_Fee, Nhs_Updated_At from Bronze (now available)
--    *03     20/05/2026  AIH Column naming convention fixes (ID/_ID, NHS, UDA, NI, SCOT)
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
        ISNULL(CAST(staged.[NHS_Claim_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Practitioner_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Treatment_Plan_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Site_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Contract_ID] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Claim_Status] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Sequence_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[UDA_Band] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Expected_UDA] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Awarded_UDA] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Patient_Charge] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Dentist_Charge] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Awarded_Dentist_Charge] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NI_Calculated_Dentist_Fee] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NI_Calculated_Patient_Fee] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[SCOT_Amount_Authorised] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[SCOT_Amount_Expected] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Ortho] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Continuation_Part_Number] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Status_Comments] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Approval_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Submitted_Date] AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[NHS_Updated_At] AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID  AS [Tenant_ID],
                LEFT(ID, 50)  AS [NHS_Claim_ID],
                -- Bronze Patient_ID is decimal(18,4); Silver is int
        TRY_CAST(ROUND(CAST(Patient_ID AS float), 0) AS int)  AS [Patient_ID],
                Practitioner_ID  AS [Practitioner_ID],
                -- Bronze Treatment_Plan_ID is decimal(18,4); Silver is int
        TRY_CAST(ROUND(CAST(Treatment_Plan_ID AS float), 0) AS int)  AS [Treatment_Plan_ID],
                LEFT(Site_ID, 50)  AS [Site_ID],
                LEFT(Contract_ID, 50)  AS [Contract_ID],
                LEFT(Claim_Status, 50)  AS [Claim_Status],
                -- Bronze Sequence_Number is decimal(18,4); Silver is int
        TRY_CAST(ROUND(CAST(Sequence_Number AS float), 0) AS int)  AS [Sequence_Number],
                -- Bronze UDA_Band is decimal(18,4); Silver is VARCHAR(10)
        LEFT(CAST(CAST(UDA_Band AS int) AS VARCHAR(10)), 10)  AS [UDA_Band],
                Expected_UDA  AS [Expected_UDA],
                Awarded_UDA  AS [Awarded_UDA],
                Patient_Charge  AS [Patient_Charge],
                Dentist_Charge  AS [Dentist_Charge],
                Awarded_Dentist_Charge  AS [Awarded_Dentist_Charge],
                NI_Calculated_Dentist_Fee  AS [NI_Calculated_Dentist_Fee],
                NI_Calculated_Patient_Fee  AS [NI_Calculated_Patient_Fee],
                Scot_Amount_Authorised  AS [SCOT_Amount_Authorised],
                Scot_Amount_Expected  AS [SCOT_Amount_Expected],
                -- Bronze Ortho is decimal(18,4); Silver is bit
        CASE WHEN Ortho = 1 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END  AS [Ortho],
                -- Bronze Continuation_Part_Number is VARCHAR(255); Silver is int
        TRY_CAST(Continuation_Part_Number AS int)  AS [Continuation_Part_Number],
                Status_Comments  AS [Status_Comments],
                TRY_CAST(Approval_Date   AS date)  AS [Approval_Date],
                TRY_CAST(Submitted_Date  AS date)  AS [Submitted_Date],
                TRY_CAST(NHS_Updated_At AS datetime2(3))  AS [NHS_Updated_At]
            FROM Bronze.NHS_Claims
        ) AS staged;

        UPDATE tgt
        SET
            [Patient_ID] = src.[Patient_ID],
            [Practitioner_ID] = src.[Practitioner_ID],
            [Treatment_Plan_ID] = src.[Treatment_Plan_ID],
            [Site_ID] = src.[Site_ID],
            [Contract_ID] = src.[Contract_ID],
            [Claim_Status] = src.[Claim_Status],
            [Sequence_Number] = src.[Sequence_Number],
            [UDA_Band] = src.[UDA_Band],
            [Expected_UDA] = src.[Expected_UDA],
            [Awarded_UDA] = src.[Awarded_UDA],
            [Patient_Charge] = src.[Patient_Charge],
            [Dentist_Charge] = src.[Dentist_Charge],
            [Awarded_Dentist_Charge] = src.[Awarded_Dentist_Charge],
            [NI_Calculated_Dentist_Fee] = src.[NI_Calculated_Dentist_Fee],
            [NI_Calculated_Patient_Fee] = src.[NI_Calculated_Patient_Fee],
            [SCOT_Amount_Authorised] = src.[SCOT_Amount_Authorised],
            [SCOT_Amount_Expected] = src.[SCOT_Amount_Expected],
            [Ortho] = src.[Ortho],
            [Continuation_Part_Number] = src.[Continuation_Part_Number],
            [Status_Comments] = src.[Status_Comments],
            [Approval_Date] = src.[Approval_Date],
            [Submitted_Date] = src.[Submitted_Date],
            [NHS_Updated_At] = src.[NHS_Updated_At],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[NHS_Claims] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[NHS_Claim_ID] = src.[NHS_Claim_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[NHS_Claims] ([Tenant_ID], [NHS_Claim_ID], [Patient_ID], [Practitioner_ID], [Treatment_Plan_ID], [Site_ID], [Contract_ID], [Claim_Status], [Sequence_Number], [UDA_Band], [Expected_UDA], [Awarded_UDA], [Patient_Charge], [Dentist_Charge], [Awarded_Dentist_Charge], [NI_Calculated_Dentist_Fee], [NI_Calculated_Patient_Fee], [SCOT_Amount_Authorised], [SCOT_Amount_Expected], [Ortho], [Continuation_Part_Number], [Status_Comments], [Approval_Date], [Submitted_Date], [NHS_Updated_At], [DW_Created_At], [DW_Updated_At], [_Row_Hash])
        SELECT src.[Tenant_ID], src.[NHS_Claim_ID], src.[Patient_ID], src.[Practitioner_ID], src.[Treatment_Plan_ID], src.[Site_ID], src.[Contract_ID], src.[Claim_Status], src.[Sequence_Number], src.[UDA_Band], src.[Expected_UDA], src.[Awarded_UDA], src.[Patient_Charge], src.[Dentist_Charge], src.[Awarded_Dentist_Charge], src.[NI_Calculated_Dentist_Fee], src.[NI_Calculated_Patient_Fee], src.[SCOT_Amount_Authorised], src.[SCOT_Amount_Expected], src.[Ortho], src.[Continuation_Part_Number], src.[Status_Comments], src.[Approval_Date], src.[Submitted_Date], src.[NHS_Updated_At], SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[NHS_Claims] AS tgt WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[NHS_Claim_ID] = src.[NHS_Claim_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[NHS_Claims] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[NHS_Claim_ID] = tgt.[NHS_Claim_ID]
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