--DECLARE x; EXEC [Audit].[usp_Clear_Tenant_Data] @Tenant_ID = 100, @Dry_Run = 1;
--------------------------------------------------------------------
--  Stored Procedure :  Audit.usp_Clear_Tenant_Data
--  Author           :  AIH
--  Initial Date     :  07/07/2026
--  History          :
--    *01     07/07/2026  AIH  Initial release. Data-only tenant clear -- step 1 of
--                             Orchestrate_Onboarding (clear -> populate stage -> build -> freeze).
--  Purpose          :  Delete ALL medallion DATA rows for one tenant -- every Tenant_ID-bearing
--                      base table in Bronze / Silver / Gold (Dim_*/Fact_*/Aggregate_*) WHERE
--                      Tenant_ID=@X. PRESERVES the tenant's identity + config: Audit.Tenants /
--                      Process_Config / Process_Dependency / Process_Execution_Log, Config.*,
--                      Input.Targets, Security.Clients / Application_Users (RLS), Meta.*,
--                      Migrate.Deploy_Log, Test.* baselines, and any GLOBAL table with no Tenant_ID
--                      column (Silver.Appointment_Reason_Map, Gold.Dim_Date) -- those are skipped
--                      automatically as the scan keys on the Tenant_ID column.
--                      This is the onboarding-safe clear: a following full pull + build-only rebuilds
--                      the tenant from a clean slate, giving what @Full_Refresh's anti-join gave
--                      WITHOUT any full-vs-delta branching in the load SPs.
--                      Does NOT touch Gold.Load_Watermark (GLOBAL, keyed by Entity_Name): the
--                      clear+rebuild re-INSERTs Silver with DW_Updated_At = now (> the watermark),
--                      and the watermark facts filter on DW_Updated_At, so this tenant is re-picked-up
--                      naturally. Resetting the shared watermark would needlessly force EVERY other
--                      tenant to full-rescan.
--                      Metadata-driven (any Bronze/Silver/Gold table with a Tenant_ID column) so it
--                      auto-covers new tables. NEVER touches the -1 sentinel or other tenants.
--                      Fabric note: STRING_AGG scalar-assign over INFORMATION_SCHEMA (no SELECT INTO
--                      #temp from catalog views, no cursors -- both rejected in distributed mode).
--  Params           :  @Tenant_ID  the tenant to clear (required; -1 refused)
--                      @Dry_Run    1 = report per-table row counts WITHOUT deleting (default 0)
--  To Run           :  EXEC Audit.usp_Clear_Tenant_Data @Tenant_ID = 100;              -- clear
--                      EXEC Audit.usp_Clear_Tenant_Data @Tenant_ID = 100, @Dry_Run = 1; -- preview
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Audit].[usp_Clear_Tenant_Data]
GO
CREATE PROCEDURE [Audit].[usp_Clear_Tenant_Data]
(
      @Tenant_ID INT
    , @Dry_Run   BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Safety guards
    IF @Tenant_ID IS NULL
        THROW 500040, 'usp_Clear_Tenant_Data:: @Tenant_ID is required.', 1;
    IF @Tenant_ID = -1
        THROW 500041, 'usp_Clear_Tenant_Data:: refusing to clear the -1 sentinel tenant.', 1;

    DECLARE @tid VARCHAR(10)   = CAST(@Tenant_ID AS VARCHAR(10));
    DECLARE @sql NVARCHAR(MAX);

    IF @Dry_Run = 1
    BEGIN
        SELECT @sql = STRING_AGG(CAST(
            'SELECT ''' + c.TABLE_SCHEMA + '.' + c.TABLE_NAME + ''' AS Table_Name, COUNT_BIG(*) AS Rows_Affected'
            + ' FROM [' + c.TABLE_SCHEMA + '].[' + c.TABLE_NAME + '] WHERE Tenant_ID = ' + @tid
            AS NVARCHAR(MAX)), CHAR(10) + 'UNION ALL ')
        FROM INFORMATION_SCHEMA.COLUMNS c
        JOIN INFORMATION_SCHEMA.TABLES  t
          ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME AND t.TABLE_TYPE = 'BASE TABLE'
        WHERE c.COLUMN_NAME = 'Tenant_ID'
          AND c.TABLE_SCHEMA IN ('Bronze', 'Silver', 'Gold');   -- medallion DATA only

        IF @sql IS NULL THROW 500042, 'usp_Clear_Tenant_Data:: no medallion tenant-bearing tables found.', 1;
        SET @sql = N'SELECT Table_Name, Rows_Affected FROM (' + @sql + N') x WHERE Rows_Affected > 0 ORDER BY Table_Name;';
        EXEC sp_executesql @sql;
    END
    ELSE
    BEGIN
        SELECT @sql = STRING_AGG(CAST(
            'DELETE FROM [' + c.TABLE_SCHEMA + '].[' + c.TABLE_NAME + '] WHERE Tenant_ID = ' + @tid + ';'
            AS NVARCHAR(MAX)), CHAR(10))
        FROM INFORMATION_SCHEMA.COLUMNS c
        JOIN INFORMATION_SCHEMA.TABLES  t
          ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME AND t.TABLE_TYPE = 'BASE TABLE'
        WHERE c.COLUMN_NAME = 'Tenant_ID'
          AND c.TABLE_SCHEMA IN ('Bronze', 'Silver', 'Gold');   -- medallion DATA only

        IF @sql IS NULL THROW 500042, 'usp_Clear_Tenant_Data:: no medallion tenant-bearing tables found.', 1;
        EXEC sp_executesql @sql;
        SELECT @Tenant_ID AS Tenant_ID, 'CLEARED' AS Mode;
    END
END
GO
