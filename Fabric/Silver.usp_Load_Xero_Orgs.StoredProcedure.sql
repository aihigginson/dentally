--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Xero_Orgs
--  Author           :  AIH
--  Initial Date     :  2026-07-03
--  History          :
--    *01     2026-07-03  AIH  Initial release (Xero org registry)
--  Notes            :  Types the Bronze org registry (all tenants). Upsert on
--                      Tenant_ID + Xero_Tenant_ID.
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Silver.usp_Load_Xero_Orgs @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Xero_Orgs]
GO
CREATE PROCEDURE [Silver].[usp_Load_Xero_Orgs]
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

        UPDATE tgt SET
              tgt.Tenant_Name     = src.Tenant_Name
            , tgt.Default_Site_ID = src.Default_Site_ID
            , tgt.DW_Updated_At   = SYSUTCDATETIME()
        FROM Silver.Xero_Orgs AS tgt
        INNER JOIN Bronze.Xero_Orgs AS src
            ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Xero_Tenant_ID = src.Xero_Tenant_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Silver.Xero_Orgs (Tenant_ID, Xero_Tenant_ID, Tenant_Name, Default_Site_ID, DW_Loaded_At, DW_Updated_At)
        SELECT src.Tenant_ID, src.Xero_Tenant_ID, src.Tenant_Name, src.Default_Site_ID, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM Bronze.Xero_Orgs AS src
        WHERE NOT EXISTS (SELECT 1 FROM Silver.Xero_Orgs tgt
                          WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Xero_Tenant_ID = src.Xero_Tenant_ID);
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
