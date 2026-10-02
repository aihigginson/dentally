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

        -- ==> WITH @Tenant_ID NULL THIS DELETES ONLY THE TENANTS PRESENT IN STAGE. <== Never
        -- "every tenant in Bronze": the demo tenant is seeded straight into Bronze and never
        -- appears in Stage, so an unscoped delete here would wipe data this run never loaded.
        DELETE FROM Bronze.Xero_Orgs
        WHERE (@Tenant_ID IS NOT NULL AND Tenant_ID = @Tenant_ID)
           OR (@Tenant_ID IS NULL
               AND Tenant_ID IN (SELECT DISTINCT TRY_CAST(Tenant_ID AS INT) FROM Stage.Xero_Orgs
                                 WHERE TRY_CAST(Tenant_ID AS INT) IN (SELECT Tenant_ID FROM Audit.Tenants WHERE Is_Active = 1)));
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Bronze.Xero_Orgs (Tenant_ID, Xero_Tenant_ID, Tenant_Name, Default_Site_ID, DW_Loaded_At)
        SELECT
              TRY_CAST(Tenant_ID AS INT)
            , LEFT(Xero_Tenant_ID,  100)
            , LEFT(Tenant_Name,     255)
            , LEFT(Default_Site_ID,  50)
            , SYSUTCDATETIME()
        FROM Stage.Xero_Orgs
        -- @Tenant_ID NULL = every ACTIVE REGISTERED tenant present in Stage. Stage is an
        -- inbound landing area and can hold tenants the product knows nothing about, so
        -- the set is intersected with Audit.Tenants rather than taken on trust. An
        -- explicit value is NOT constrained -- that is the operator escape hatch.
        WHERE (   (@Tenant_ID IS NOT NULL AND TRY_CAST(Tenant_ID AS INT) = @Tenant_ID)
           OR (@Tenant_ID IS NULL AND TRY_CAST(Tenant_ID AS INT) IN
                 (SELECT Tenant_ID FROM Audit.Tenants WHERE Is_Active = 1)));
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
