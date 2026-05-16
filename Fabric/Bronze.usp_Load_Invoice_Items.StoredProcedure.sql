--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_Invoice_Items] @Tenant_ID=1, @Full_Refresh=1, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Invoice_Items
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Invoice_Items @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Invoice_Items]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Invoice_Items]
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
              TRY_CAST(tenant_id     AS INT)                               AS Tenant_ID
            , LEFT(id,                 255)                                AS ID
            , TRY_CAST(invoice_id    AS INT)                               AS Invoice_ID
            , TRY_CAST(practitioner_id AS INT)                             AS Practitioner_ID
            , LEFT(treatment_name,     255)                                AS Name
            , CAST(TRY_CAST(price    AS DECIMAL(18,4)) AS INT)             AS Item_Price
            , CAST(TRY_CAST(nhs_charge AS DECIMAL(18,4)) AS INT)           AS NHS_Charge
            , TRY_CAST(quantity      AS INT)                               AS Quantity
            , LEFT(created_at,         255)                                AS Created_At
            , LEFT(updated_at,         255)                                AS Updated_At
        INTO #src
        FROM Stage.Invoice_Items
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Invoice_ID      = src.Invoice_ID
            , tgt.Practitioner_ID = src.Practitioner_ID
            , tgt.Name            = src.Name
            , tgt.Item_Price      = src.Item_Price
            , tgt.NHS_Charge      = src.NHS_Charge
            , tgt.Quantity        = src.Quantity
            , tgt.Created_At      = src.Created_At
            , tgt.Updated_At      = src.Updated_At
            , tgt.DW_Loaded_At    = SYSUTCDATETIME()
        FROM Bronze.Invoice_Items AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Invoice_Items (Tenant_ID, ID, Invoice_ID, Practitioner_ID, Name, Item_Price, NHS_Charge, Quantity, Created_At, Updated_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Invoice_ID, src.Practitioner_ID, src.Name, src.Item_Price, src.NHS_Charge, src.Quantity, src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Invoice_Items tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Invoice_Items AS tgt
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
