--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Fees
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
--    *02     30/04/2026  AIH Fix source column id → fee_id to match mock API field name
--    *03     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *04     16/05/2026  AIH Revert fee_id → id: 4-tenant rebuild restored standard id field name
--    *05     02/06/2026  AIH Boolean columns stored raw (VARCHAR) in Bronze; cast moved to Silver
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Fees]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Fees]
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
              TRY_CAST(tenant_id AS INT)                                                                    AS Tenant_ID
            , LEFT(id, 255)                                                                                AS Fee_ID
            , TRY_CAST(payment_plan_id AS INT)                                                              AS Payment_Plan_ID
            , TRY_CAST(treatment_id AS DECIMAL(18,4))                                                       AS Treatment_ID
            , LEFT(multiple_pricing, 255)                                                                   AS Multiple_Pricing
            , TRY_CAST(duration_one   AS INT)                                                               AS Duration_One
            , TRY_CAST(duration_two   AS INT)                                                               AS Duration_Two
            , TRY_CAST(duration_three AS INT)                                                               AS Duration_Three
            , TRY_CAST(duration_four  AS INT)                                                               AS Duration_Four
            , TRY_CAST(duration_five  AS INT)                                                               AS Duration_Five
            , LEFT(price_one,   255)                                                                        AS Price_One
            , LEFT(price_two,   255)                                                                        AS Price_Two
            , LEFT(price_three, 255)                                                                        AS Price_Three
            , LEFT(price_four,  255)                                                                        AS Price_Four
            , LEFT(price_five,  255)                                                                        AS Price_Five
        INTO #src
        FROM Stage.Fees
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Payment_Plan_ID  = src.Payment_Plan_ID
            , tgt.Treatment_ID     = src.Treatment_ID
            , tgt.Multiple_Pricing = src.Multiple_Pricing
            , tgt.Duration_One     = src.Duration_One
            , tgt.Duration_Two     = src.Duration_Two
            , tgt.Duration_Three   = src.Duration_Three
            , tgt.Duration_Four    = src.Duration_Four
            , tgt.Duration_Five    = src.Duration_Five
            , tgt.Price_One        = src.Price_One
            , tgt.Price_Two        = src.Price_Two
            , tgt.Price_Three      = src.Price_Three
            , tgt.Price_Four       = src.Price_Four
            , tgt.Price_Five       = src.Price_Five
            , tgt.DW_Loaded_At     = SYSUTCDATETIME()
        FROM Bronze.Fees AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Fee_ID = src.Fee_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Fees (Tenant_ID, Fee_ID, Payment_Plan_ID, Treatment_ID, Multiple_Pricing, Duration_One, Duration_Two, Duration_Three, Duration_Four, Duration_Five, Price_One, Price_Two, Price_Three, Price_Four, Price_Five, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Fee_ID, src.Payment_Plan_ID, src.Treatment_ID, src.Multiple_Pricing, src.Duration_One, src.Duration_Two, src.Duration_Three, src.Duration_Four, src.Duration_Five, src.Price_One, src.Price_Two, src.Price_Three, src.Price_Four, src.Price_Five, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Fees tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Fee_ID = src.Fee_ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Fees AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE Fee_ID = tgt.Fee_ID);
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
