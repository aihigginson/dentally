--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Payment_Explanations
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Payment_Explanations]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Payment_Explanations]
(
      @Tenant_ID    INT
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
              TRY_CAST(tenant_id AS INT)                          AS Tenant_ID
            , LEFT(id, 255)                                       AS ID
            , TRY_CAST(amount AS DECIMAL(18,4))                   AS Amount
            , LEFT(comments, 4000)                                AS Comments
            , TRY_CAST(invoice_id AS INT)                         AS Invoice_ID
            , LEFT(invoice_reference, 4000)                       AS Invoice_Reference
            , TRY_CAST(payment_id AS INT)                         AS Payment_ID
            , LEFT(payment_reference, 4000)                       AS Payment_Reference
            , TRY_CAST(user_id AS INT)                            AS User_ID
        INTO #src
        FROM Stage.Payment_Explanations
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Amount             = src.Amount
            , tgt.Comments           = src.Comments
            , tgt.Invoice_ID         = src.Invoice_ID
            , tgt.Invoice_Reference  = src.Invoice_Reference
            , tgt.Payment_ID         = src.Payment_ID
            , tgt.Payment_Reference  = src.Payment_Reference
            , tgt.User_ID            = src.User_ID
            , tgt.DW_Loaded_At       = SYSUTCDATETIME()
        FROM Bronze.Payment_Explanations AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Payment_Explanations (Tenant_ID, ID, Amount, Comments, Invoice_ID, Invoice_Reference, Payment_ID, Payment_Reference, User_ID, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Amount, src.Comments, src.Invoice_ID, src.Invoice_Reference, src.Payment_ID, src.Payment_Reference, src.User_ID, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Payment_Explanations tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;


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
