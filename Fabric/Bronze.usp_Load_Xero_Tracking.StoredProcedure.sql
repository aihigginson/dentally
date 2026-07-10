--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Xero_Tracking
--  Author           :  AIH
--  Initial Date     :  2026-07-03
--  History          :
--    *01     2026-07-03  AIH  Initial release (Xero tracking categories + options)
--  Notes            :  Snapshot source (xero_land.py overwrites the stage each run).
--                      Full refresh per tenant: delete the tenant's rows, insert current.
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Bronze.usp_Load_Xero_Tracking @Tenant_ID=99,@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Xero_Tracking]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Xero_Tracking]
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

        DELETE FROM Bronze.Xero_Tracking WHERE Tenant_ID = @Tenant_ID;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Bronze.Xero_Tracking (Tenant_ID, Xero_Tenant_ID, Tracking_Category_ID, Category_Name, Category_Status, Tracking_Option_ID, Option_Name, Option_Status, DW_Loaded_At)
        SELECT
              TRY_CAST(Tenant_ID AS INT)
            , LEFT(Xero_Tenant_ID,       100)
            , LEFT(Tracking_Category_ID, 100)
            , LEFT(Category_Name,        255)
            , LEFT(Category_Status,       50)
            , LEFT(Tracking_Option_ID,   100)
            , LEFT(Option_Name,          255)
            , LEFT(Option_Status,         50)
            , SYSUTCDATETIME()
        FROM Stage.Xero_Tracking
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
