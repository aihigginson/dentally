--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_GL_Account
--  Author           :  AIH
--  Initial Date     :  2026-07-01
--  History          :
--    *01     2026-07-01  AIH  Initial release (Xero profitability slice)
--  Notes            :  Upsert from Silver.Xero_Accounts (all tenants). pk assigned via
--                      MAX+ROW_NUMBER (no IDENTITY); -1 unknown seed protected.
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Gold.usp_Load_Dim_GL_Account @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_GL_Account]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_GL_Account]
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

        SELECT Tenant_ID, Account_ID, Code, Name, Account_Type, Account_Class,
               PL_Group, Is_PL, EBITDA_Item, Reporting_Code, Reporting_Code_Name, Status
        INTO #src
        FROM Silver.Xero_Accounts;

        UPDATE tgt SET
              tgt.Account_Code        = src.Code
            , tgt.Account_Name        = src.Name
            , tgt.Account_Type        = src.Account_Type
            , tgt.Account_Class       = src.Account_Class
            , tgt.PL_Group            = src.PL_Group
            , tgt.Is_PL               = src.Is_PL
            , tgt.EBITDA_Item         = src.EBITDA_Item
            , tgt.Reporting_Code      = src.Reporting_Code
            , tgt.Reporting_Code_Name = src.Reporting_Code_Name
            , tgt.Status              = src.Status
            , tgt.DW_Updated_At       = SYSUTCDATETIME()
        FROM Gold.Dim_GL_Account AS tgt
        INNER JOIN #src AS src ON tgt.bk_Account_ID = src.Account_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE tgt.pk_GL_Account <> -1;
        SET @My_Updates = @@ROWCOUNT;

        DECLARE @base BIGINT = ISNULL((SELECT MAX(pk_GL_Account) FROM Gold.Dim_GL_Account WHERE pk_GL_Account > 0), 0);
        INSERT INTO Gold.Dim_GL_Account (pk_GL_Account, Tenant_ID, bk_Account_ID, Account_Code, Account_Name, Account_Type, Account_Class, PL_Group, Is_PL, EBITDA_Item, Reporting_Code, Reporting_Code_Name, Status, DW_Created_At, DW_Updated_At)
        SELECT
              @base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Account_ID)
            , src.Tenant_ID, src.Account_ID, src.Code, src.Name, src.Account_Type, src.Account_Class
            , src.PL_Group, src.Is_PL, src.EBITDA_Item, src.Reporting_Code, src.Reporting_Code_Name, src.Status
            , SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_GL_Account tgt WHERE tgt.bk_Account_ID = src.Account_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        -- Unknown / -1 seed row (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_GL_Account (pk_GL_Account, Tenant_ID, bk_Account_ID, Account_Code, Account_Name, Is_PL, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, '-1', '-1', 'Unknown', 0, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_GL_Account WHERE pk_GL_Account = -1);

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
