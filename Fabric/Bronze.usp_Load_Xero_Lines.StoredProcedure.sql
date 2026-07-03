--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Xero_Lines
--  Author           :  AIH
--  Initial Date     :  2026-07-01
--  History          :
--    *01     2026-07-01  AIH  Initial release (Xero profitability slice)
--  Notes            :  Snapshot source (xero_land.py overwrites the stage table each
--                      run) and line grain has no stable incremental key, so this is a
--                      full refresh per tenant: delete the tenant's rows, insert current.
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Bronze.usp_Load_Xero_Lines @Tenant_ID=99,@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Xero_Lines]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Xero_Lines]
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

        DELETE FROM Bronze.Xero_Lines WHERE Tenant_ID = @Tenant_ID;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Bronze.Xero_Lines (Tenant_ID, Xero_Tenant_ID, Source, Doc_ID, Doc_Number, Doc_Type, Doc_Status, Doc_Date, Contact_Name, Line_Amount_Types, Line_Item_ID, Account_Code, Account_ID, Description, Line_Amount, Tax_Amount, Tracking, Tracking_Cat_1, Tracking_Opt_1, Tracking_Cat_2, Tracking_Opt_2, DW_Loaded_At)
        SELECT
              TRY_CAST(Tenant_ID AS INT)
            , LEFT(Xero_Tenant_ID,     100)
            , LEFT(Source,              30)
            , LEFT(Doc_ID,             100)
            , LEFT(Doc_Number,         100)
            , LEFT(Doc_Type,            30)
            , LEFT(Doc_Status,          30)
            , LEFT(Doc_Date,            30)
            , LEFT(Contact_Name,       255)
            , LEFT(Line_Amount_Types,   30)
            , LEFT(Line_Item_ID,       100)
            , LEFT(Account_Code,        50)
            , LEFT(Account_ID,         100)
            , LEFT(Description,        500)
            , TRY_CAST(Line_Amount AS DECIMAL(18,4))
            , TRY_CAST(Tax_Amount  AS DECIMAL(18,4))
            , LEFT(Tracking,           500)
            , LEFT(Tracking_Cat_1,     255)
            , LEFT(Tracking_Opt_1,     255)
            , LEFT(Tracking_Cat_2,     255)
            , LEFT(Tracking_Opt_2,     255)
            , SYSUTCDATETIME()
        FROM Stage.Xero_Lines
        WHERE TRY_CAST(Tenant_ID AS INT) = @Tenant_ID;
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
