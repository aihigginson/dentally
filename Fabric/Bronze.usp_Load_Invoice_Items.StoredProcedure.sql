--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Invoice_Items
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *03     16/05/2026  AIH Fix field names (item_price, name); add missing columns (Total_Price, Sundry_ID, Treatment_Plan_ID, Treatment_Plan_Item_ID, User_ID)
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
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id               AS INT)           AS Tenant_ID
            , LEFT(id,                           255)            AS ID
            , TRY_CAST(invoice_id              AS INT)           AS Invoice_ID
            , TRY_CAST(practitioner_id         AS INT)           AS Practitioner_ID
            , TRY_CAST(treatment_plan_id       AS INT)           AS Treatment_Plan_ID
            , LEFT(treatment_plan_item_id,       255)            AS Treatment_Plan_Item_ID
            , TRY_CAST(user_id                 AS INT)           AS User_ID
            , LEFT(sundry_id,                    255)            AS Sundry_ID
            , LEFT(name,                         255)            AS Name
            , TRY_CAST(item_price              AS DECIMAL(18,4)) AS Item_Price
            -- Real Dentally sends nhs_charge as a boolean ('True'/'False'); the mock sent a numeric.
            -- Map bool -> 1/0 (Silver treats it as a bit flag; NHS Revenue = NHS_Charge > 0), with a
            -- numeric fallback so any numeric source still classifies. Was CAST(TRY_CAST(... DECIMAL) AS INT),
            -- which nulled every real 'True'/'False' and blanked NHS Revenue.
            , CASE WHEN LOWER(LTRIM(RTRIM(nhs_charge))) IN ('true','1')  THEN 1
                   WHEN LOWER(LTRIM(RTRIM(nhs_charge))) IN ('false','0') THEN 0
                   ELSE CAST(TRY_CAST(nhs_charge AS DECIMAL(18,4)) AS INT) END AS NHS_Charge
            , TRY_CAST(quantity                AS INT)           AS Quantity
            , TRY_CAST(total_price             AS DECIMAL(18,4)) AS Total_Price
            , LEFT(created_at,                   255)            AS Created_At
            , LEFT(updated_at,                   255)            AS Updated_At
        INTO #src
        FROM Stage.Invoice_Items
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Invoice_ID             = src.Invoice_ID
            , tgt.Practitioner_ID        = src.Practitioner_ID
            , tgt.Treatment_Plan_ID      = src.Treatment_Plan_ID
            , tgt.Treatment_Plan_Item_ID = src.Treatment_Plan_Item_ID
            , tgt.User_ID               = src.User_ID
            , tgt.Sundry_ID             = src.Sundry_ID
            , tgt.Name                  = src.Name
            , tgt.Item_Price            = src.Item_Price
            , tgt.NHS_Charge            = src.NHS_Charge
            , tgt.Quantity              = src.Quantity
            , tgt.Total_Price           = src.Total_Price
            , tgt.Created_At            = src.Created_At
            , tgt.Updated_At            = src.Updated_At
            , tgt.DW_Loaded_At          = SYSUTCDATETIME()
        FROM Bronze.Invoice_Items AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Invoice_Items (Tenant_ID, ID, Invoice_ID, Practitioner_ID, Treatment_Plan_ID, Treatment_Plan_Item_ID, User_ID, Sundry_ID, Name, Item_Price, NHS_Charge, Quantity, Total_Price, Created_At, Updated_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Invoice_ID, src.Practitioner_ID, src.Treatment_Plan_ID, src.Treatment_Plan_Item_ID, src.User_ID, src.Sundry_ID, src.Name, src.Item_Price, src.NHS_Charge, src.Quantity, src.Total_Price, src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Invoice_Items tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
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
