--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Patient_Referral_Reasons
--  Author           :  AIH
--  Initital Date    :  19/05/2026
--  History          :
--    *01     19/05/2026  AIH Initial Release
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Patient_Referral_Reasons]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Patient_Referral_Reasons]
(
      @Tenant_ID    INT
    , @Full_Refresh BIT              = 0
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id           AS INT)            AS Tenant_ID
            , TRY_CAST(patient_referral_id AS DECIMAL(18,4))  AS Patient_Referral_ID
            , LEFT(referral_reason_id,        255)             AS Referral_Reason_ID
            , LEFT(name,                      255)             AS Name
        INTO #src
        FROM Stage.Patient_Referral_Reasons
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Name           = src.Name
            , tgt.DW_Loaded_At   = SYSUTCDATETIME()
        FROM Bronze.Patient_Referral_Reasons AS tgt
        INNER JOIN #src AS src
            ON tgt.Tenant_ID           = src.Tenant_ID
           AND tgt.Patient_Referral_ID = src.Patient_Referral_ID
           AND tgt.Referral_Reason_ID  = src.Referral_Reason_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Patient_Referral_Reasons (Tenant_ID, Patient_Referral_ID, Referral_Reason_ID, Name, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Patient_Referral_ID, src.Referral_Reason_ID, src.Name, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM Bronze.Patient_Referral_Reasons tgt
            WHERE tgt.Tenant_ID           = src.Tenant_ID
              AND tgt.Patient_Referral_ID = src.Patient_Referral_ID
              AND tgt.Referral_Reason_ID  = src.Referral_Reason_ID
        );
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Patient_Referral_Reasons AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (
                SELECT 1 FROM #src
                WHERE Patient_Referral_ID = tgt.Patient_Referral_ID
                  AND Referral_Reason_ID  = tgt.Referral_Reason_ID
              );
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
