--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Xero_Accounts
--  Author           :  AIH
--  Initial Date     :  2026-07-01
--  History          :
--    *01     2026-07-01  AIH  Initial release (Xero profitability slice)
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Bronze.usp_Load_Xero_Accounts @Tenant_ID=99,@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Xero_Accounts]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Xero_Accounts]
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
              TRY_CAST(Tenant_ID AS INT)               AS Tenant_ID
            , LEFT(Xero_Tenant_ID,      100)           AS Xero_Tenant_ID
            , LEFT(Account_ID,          100)           AS Account_ID
            , LEFT(Code,                 50)           AS Code
            , LEFT(Name,                255)           AS Name
            , LEFT([Type],               50)           AS Account_Type
            , LEFT([Class],              50)           AS Account_Class
            , LEFT(Reporting_Code,       50)           AS Reporting_Code
            , LEFT(Reporting_Code_Name, 255)           AS Reporting_Code_Name
            , LEFT(Status,               50)           AS Status
        INTO #src
        FROM Stage.Xero_Accounts
        WHERE TRY_CAST(Tenant_ID AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Xero_Tenant_ID      = src.Xero_Tenant_ID
            , tgt.Code                = src.Code
            , tgt.Name                = src.Name
            , tgt.Account_Type        = src.Account_Type
            , tgt.Account_Class       = src.Account_Class
            , tgt.Reporting_Code      = src.Reporting_Code
            , tgt.Reporting_Code_Name = src.Reporting_Code_Name
            , tgt.Status              = src.Status
            , tgt.DW_Loaded_At        = SYSUTCDATETIME()
        FROM Bronze.Xero_Accounts AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Account_ID = src.Account_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Xero_Accounts (Tenant_ID, Xero_Tenant_ID, Account_ID, Code, Name, Account_Type, Account_Class, Reporting_Code, Reporting_Code_Name, Status, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Xero_Tenant_ID, src.Account_ID, src.Code, src.Name, src.Account_Type, src.Account_Class, src.Reporting_Code, src.Reporting_Code_Name, src.Status, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Xero_Accounts tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Account_ID = src.Account_ID);
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
