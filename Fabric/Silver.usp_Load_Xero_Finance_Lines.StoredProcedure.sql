--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Xero_Finance_Lines
--  Author           :  AIH
--  Initial Date     :  2026-07-01
--  History          :
--    *01     2026-07-01  AIH  Initial release (Xero profitability slice)
--    *02     2026-07-01  AIH  All-tenant @Mode signature (house Silver / orchestration);
--                             full rebuild across all tenants.
--  Notes            :  Ports API/xero_model.py (reconciled to Xero's P&L). Keeps only
--                      P&L-affecting lines (join to Is_PL accounts, status
--                      AUTHORISED/PAID/POSTED -> drops DRAFT/DELETED/VOIDED). Net_Amount
--                      strips tax on tax-inclusive lines. PL_Amount is the signed P&L
--                      contribution: inflow (ACCREC/RECEIVE, +) vs outflow (ACCPAY/SPEND)
--                      relative to account class. Full rebuild (snapshot source).
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Silver.usp_Load_Xero_Finance_Lines @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Xero_Finance_Lines]
GO
CREATE PROCEDURE [Silver].[usp_Load_Xero_Finance_Lines]
(
      @Mode         VARCHAR(100)     = 'TEST'
    , @Logging      SMALLINT         = 1
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

        DELETE FROM Silver.Xero_Finance_Lines;
        SET @My_Deletes = @@ROWCOUNT;

        WITH src AS (
            SELECT
                  l.Tenant_ID, l.Xero_Tenant_ID, l.Source, l.Doc_ID, l.Doc_Number,
                  l.Doc_Type, l.Doc_Status, l.Doc_Date, l.Contact_Name,
                  l.Account_ID, l.Account_Code, l.Description, l.Line_Item_ID, l.Line_Amount,
                  a.Account_Class, a.PL_Group,
                  CASE WHEN l.Line_Amount_Types = 'Inclusive'
                       THEN l.Line_Amount - ISNULL(l.Tax_Amount, 0)
                       ELSE l.Line_Amount END AS Net_Amount,
                  CASE l.Doc_Type
                       WHEN 'ACCREC'       THEN  1
                       WHEN 'RECEIVE'      THEN  1
                       WHEN 'ACCPAYCREDIT' THEN  1
                       WHEN 'ACCPAY'       THEN -1
                       WHEN 'SPEND'        THEN -1
                       WHEN 'ACCRECCREDIT' THEN -1
                       ELSE 0 END AS Direction
            FROM Bronze.Xero_Lines AS l
            INNER JOIN Silver.Xero_Accounts AS a
                ON a.Tenant_ID = l.Tenant_ID AND a.Code = l.Account_Code AND a.Is_PL = 1
            WHERE l.Doc_Status IN ('AUTHORISED', 'PAID', 'POSTED')
        )
        INSERT INTO Silver.Xero_Finance_Lines (Tenant_ID, Xero_Tenant_ID, Source, Doc_ID, Doc_Number, Doc_Type, Doc_Status, Doc_Date, Contact_Name, Account_ID, Account_Code, Account_Class, PL_Group, Description, Net_Amount, PL_Amount, Line_Item_ID, DW_Loaded_At)
        SELECT
              Tenant_ID, Xero_Tenant_ID, Source, Doc_ID, Doc_Number, Doc_Type, Doc_Status,
              TRY_CAST(Doc_Date AS DATE), Contact_Name, Account_ID, Account_Code, Account_Class, PL_Group, Description,
              Net_Amount,
              CASE
                  WHEN Doc_Type = 'MANJRNL'
                       THEN CASE WHEN Account_Class = 'REVENUE' THEN -Line_Amount ELSE Line_Amount END
                  ELSE Net_Amount * CASE WHEN Account_Class = 'REVENUE' THEN Direction ELSE -Direction END
              END AS PL_Amount,
              Line_Item_ID, SYSUTCDATETIME()
        FROM src;
        SET @My_Inserts = @@ROWCOUNT;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
