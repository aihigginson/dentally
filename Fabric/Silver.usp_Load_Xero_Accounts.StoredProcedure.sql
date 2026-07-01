--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Xero_Accounts
--  Author           :  AIH
--  Initial Date     :  2026-07-01
--  History          :
--    *01     2026-07-01  AIH  Initial release (Xero profitability slice)
--    *02     2026-07-01  AIH  All-tenant @Mode signature (house Silver pattern /
--                             orchestration); derives PL_Group / Is_PL.
--  Notes            :  Types the Bronze chart of accounts (all tenants) and derives
--                      PL_Group / Is_PL from account Class + Type. Upsert on
--                      Tenant_ID + Account_ID.
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Silver.usp_Load_Xero_Accounts @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Xero_Accounts]
GO
CREATE PROCEDURE [Silver].[usp_Load_Xero_Accounts]
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

        SELECT
              Tenant_ID
            , Xero_Tenant_ID
            , Account_ID
            , Code
            , Name
            , Account_Type
            , Account_Class
            , CASE
                  WHEN Account_Class = 'REVENUE'                                    THEN 'Income'
                  WHEN Account_Class = 'EXPENSE' AND Account_Type = 'DIRECTCOSTS'   THEN 'Cost of Sales'
                  WHEN Account_Class = 'EXPENSE'                                    THEN 'Operating Expenses'
                  ELSE NULL
              END AS PL_Group
            , CASE WHEN Account_Class IN ('REVENUE', 'EXPENSE') THEN 1 ELSE 0 END AS Is_PL
            , Reporting_Code
            , Reporting_Code_Name
            , Status
        INTO #src
        FROM Bronze.Xero_Accounts;

        UPDATE tgt SET
              tgt.Xero_Tenant_ID      = src.Xero_Tenant_ID
            , tgt.Code                = src.Code
            , tgt.Name                = src.Name
            , tgt.Account_Type        = src.Account_Type
            , tgt.Account_Class       = src.Account_Class
            , tgt.PL_Group            = src.PL_Group
            , tgt.Is_PL               = src.Is_PL
            , tgt.Reporting_Code      = src.Reporting_Code
            , tgt.Reporting_Code_Name = src.Reporting_Code_Name
            , tgt.Status              = src.Status
            , tgt.DW_Updated_At       = SYSUTCDATETIME()
        FROM Silver.Xero_Accounts AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Account_ID = src.Account_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Silver.Xero_Accounts (Tenant_ID, Xero_Tenant_ID, Account_ID, Code, Name, Account_Type, Account_Class, PL_Group, Is_PL, Reporting_Code, Reporting_Code_Name, Status, DW_Loaded_At, DW_Updated_At)
        SELECT src.Tenant_ID, src.Xero_Tenant_ID, src.Account_ID, src.Code, src.Name, src.Account_Type, src.Account_Class, src.PL_Group, src.Is_PL, src.Reporting_Code, src.Reporting_Code_Name, src.Status, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Silver.Xero_Accounts tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Account_ID = src.Account_ID);
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
