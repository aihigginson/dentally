--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Xero_Orgs
--  Author           :  AIH
--  Initial Date     :  2026-07-03
--  History          :
--    *01     2026-07-03  AIH  Initial release (Xero org -> Tenant_ID + default site)
--  Notes            :  Snapshot source (xero_land.py overwrites the stage each run).
--                      Full refresh per tenant: delete the tenant's rows, insert current.
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Bronze.usp_Load_Xero_Orgs @Tenant_ID=99,@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Xero_Orgs]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Xero_Orgs]
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

        DELETE FROM Bronze.Xero_Orgs WHERE Tenant_ID = @Tenant_ID;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Bronze.Xero_Orgs (Tenant_ID, Xero_Tenant_ID, Tenant_Name, Default_Site_ID, DW_Loaded_At)
        SELECT
              TRY_CAST(Tenant_ID AS INT)
            , LEFT(Xero_Tenant_ID,  100)
            , LEFT(Tenant_Name,     255)
            , LEFT(Default_Site_ID,  50)
            , SYSUTCDATETIME()
        FROM Stage.Xero_Orgs
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
