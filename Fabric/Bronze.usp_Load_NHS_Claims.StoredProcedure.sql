--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_NHS_Claims] @Tenant_ID=1, @Full_Refresh=1, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_NHS_Claims
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_NHS_Claims]
GO
CREATE PROCEDURE [Bronze].[usp_Load_NHS_Claims]
(
      @Tenant_ID    INT
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
    , @Full_Refresh BIT    = 0
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id AS INT)                          AS Tenant_ID
            , LEFT(id, 255)                                       AS ID
            , TRY_CAST(awarded_uda AS DECIMAL(18,4))              AS Awarded_UDA
            , LEFT(approval_date, 255)                            AS Approval_Date
            , LEFT(contract_id, 255)                              AS Contract_ID
            , LEFT(claim_status, 255)                             AS Claim_Status
            , TRY_CAST(expected_uda AS DECIMAL(18,4))             AS Expected_UDA
            , TRY_CAST(patient_id AS DECIMAL(18,4))               AS Patient_ID
            , TRY_CAST(practitioner_id AS INT)                    AS Practitioner_ID
            , TRY_CAST(sequence_number AS DECIMAL(18,4))          AS Sequence_Number
            , LEFT(site_id, 255)                                  AS Site_ID
            , LEFT(status_comments, 255)                          AS Status_Comments
            , TRY_CAST(treatment_plan_id AS DECIMAL(18,4))        AS Treatment_Plan_ID
            , LEFT(submitted_date, 255)                           AS Submitted_Date
            , TRY_CAST(patient_charge AS DECIMAL(18,4))           AS Patient_Charge
            , TRY_CAST(scot_amount_authorised AS DECIMAL(18,4))   AS Scot_Amount_Authorised
            , TRY_CAST(scot_amount_expected AS DECIMAL(18,4))     AS Scot_Amount_Expected
            , TRY_CAST(uda_band AS DECIMAL(18,4))                 AS UDA_Band
            , TRY_CAST(ortho AS DECIMAL(18,4))                    AS Ortho
            , LEFT(continuation_part_number, 255)                 AS Continuation_Part_Number
            , LEFT(created_at, 255)                               AS Created_At
            , LEFT(updated_at, 255)                               AS Updated_At
        INTO #src
        FROM Stage.NHS_Claims
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Awarded_UDA              = src.Awarded_UDA
            , tgt.Approval_Date            = src.Approval_Date
            , tgt.Contract_ID              = src.Contract_ID
            , tgt.Claim_Status             = src.Claim_Status
            , tgt.Expected_UDA             = src.Expected_UDA
            , tgt.Patient_ID               = src.Patient_ID
            , tgt.Practitioner_ID          = src.Practitioner_ID
            , tgt.Sequence_Number          = src.Sequence_Number
            , tgt.Site_ID                  = src.Site_ID
            , tgt.Status_Comments          = src.Status_Comments
            , tgt.Treatment_Plan_ID        = src.Treatment_Plan_ID
            , tgt.Submitted_Date           = src.Submitted_Date
            , tgt.Patient_Charge           = src.Patient_Charge
            , tgt.Scot_Amount_Authorised   = src.Scot_Amount_Authorised
            , tgt.Scot_Amount_Expected     = src.Scot_Amount_Expected
            , tgt.UDA_Band                 = src.UDA_Band
            , tgt.Ortho                    = src.Ortho
            , tgt.Continuation_Part_Number = src.Continuation_Part_Number
            , tgt.Updated_At               = src.Updated_At
            , tgt.DW_Loaded_At             = SYSUTCDATETIME()
        FROM Bronze.NHS_Claims AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.NHS_Claims (Tenant_ID, ID, Awarded_UDA, Approval_Date, Contract_ID, Claim_Status, Expected_UDA, Patient_ID, Practitioner_ID, Sequence_Number, Site_ID, Status_Comments, Treatment_Plan_ID, Submitted_Date, Patient_Charge, Scot_Amount_Authorised, Scot_Amount_Expected, UDA_Band, Ortho, Continuation_Part_Number, Created_At, Updated_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Awarded_UDA, src.Approval_Date, src.Contract_ID, src.Claim_Status, src.Expected_UDA, src.Patient_ID, src.Practitioner_ID, src.Sequence_Number, src.Site_ID, src.Status_Comments, src.Treatment_Plan_ID, src.Submitted_Date, src.Patient_Charge, src.Scot_Amount_Authorised, src.Scot_Amount_Expected, src.UDA_Band, src.Ortho, src.Continuation_Part_Number, src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.NHS_Claims tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.NHS_Claims AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = tgt.ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH THROW; END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
