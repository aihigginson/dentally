--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Xero_Tracking
--  Author           :  AIH
--  Initial Date     :  2026-07-03
--  History          :
--    *01     2026-07-03  AIH  Initial release (Xero tracking reference data)
--  Notes            :  Small reference set (tracking categories + options). Full
--                      rebuild across all tenants each run.
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Silver.usp_Load_Xero_Tracking @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Xero_Tracking]
GO
CREATE PROCEDURE [Silver].[usp_Load_Xero_Tracking]
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

        DELETE FROM Silver.Xero_Tracking;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Silver.Xero_Tracking (Tenant_ID, Xero_Tenant_ID, Tracking_Category_ID, Category_Name, Category_Status, Tracking_Option_ID, Option_Name, Option_Status, DW_Loaded_At, DW_Updated_At)
        SELECT Tenant_ID, Xero_Tenant_ID, Tracking_Category_ID, Category_Name, Category_Status, Tracking_Option_ID, Option_Name, Option_Status, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM Bronze.Xero_Tracking;
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
