--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Payment_Allocations
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Payment_Allocations]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Payment_Allocations]
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
            , TRY_CAST(amount AS DECIMAL(18,4))                   AS Amount
            , LEFT(created_at, 255)                               AS Created_At
            , LEFT(description, 255)                              AS Description
            , LEFT(invoice_item_id, 255)                          AS Invoice_Item_ID
            , TRY_CAST(patient_id AS DECIMAL(18,4))               AS Patient_ID
            , TRY_CAST(payment_explanation_id AS DECIMAL(18,4))   AS Payment_Explanation_ID
            , LEFT(reversal_of_id, 255)                           AS Reversal_Of_ID
            , LEFT(transfer_from_id, 255)                         AS Transfer_From_ID
            , LEFT(transfer_from_type, 255)                       AS Transfer_From_Type
            , LEFT(transfer_to_id, 255)                           AS Transfer_To_ID
            , LEFT(transfer_to_type, 255)                         AS Transfer_To_Type
            , LEFT(updated_at, 255)                               AS Updated_At
        INTO #src
        FROM Stage.Payment_Allocations
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Amount                 = src.Amount
            , tgt.Description            = src.Description
            , tgt.Invoice_Item_ID        = src.Invoice_Item_ID
            , tgt.Patient_ID             = src.Patient_ID
            , tgt.Payment_Explanation_ID = src.Payment_Explanation_ID
            , tgt.Reversal_Of_ID         = src.Reversal_Of_ID
            , tgt.Transfer_From_ID       = src.Transfer_From_ID
            , tgt.Transfer_From_Type     = src.Transfer_From_Type
            , tgt.Transfer_To_ID         = src.Transfer_To_ID
            , tgt.Transfer_To_Type       = src.Transfer_To_Type
            , tgt.Updated_At             = src.Updated_At
            , tgt.DW_Loaded_At           = SYSUTCDATETIME()
        FROM Bronze.Payment_Allocations AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Payment_Allocations (Tenant_ID, ID, Amount, Created_At, Description, Invoice_Item_ID, Patient_ID, Payment_Explanation_ID, Reversal_Of_ID, Transfer_From_ID, Transfer_From_Type, Transfer_To_ID, Transfer_To_Type, Updated_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Amount, src.Created_At, src.Description, src.Invoice_Item_ID, src.Patient_ID, src.Payment_Explanation_ID, src.Reversal_Of_ID, src.Transfer_From_ID, src.Transfer_From_Type, src.Transfer_To_ID, src.Transfer_To_Type, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Payment_Allocations tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Payment_Allocations AS tgt
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
