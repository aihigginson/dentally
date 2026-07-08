--DECLARE x; EXEC [Audit].[usp_Delete_All_Tenant] @Tenant_ID = 15, @Dry_Run = 1;
--------------------------------------------------------------------
--  Stored Procedure :  Audit.usp_Delete_All_Tenant
--  Author           :  AIH
--  Initial Date     :  21/06/2026
--  History          :
--    *01     21/06/2026  AIH  Initial release.
--    *02     07/07/2026  AIH  Refactor: the medallion data-clear now delegates to
--                             Audit.usp_Clear_Tenant_Data (single source of truth for the data-row
--                             list -- no drift); this SP adds only the identity/config deletes
--                             (tenant-bearing tables OUTSIDE Bronze/Silver/Gold). = clear + metadata.
--  Purpose          :  Delete ALL rows for one tenant across EVERY tenant-bearing table in
--                      ALL schemas -- Bronze/Silver/Gold data PLUS Audit.Tenants registration
--                      and Config/Input/Security per-tenant config, targets and RLS mappings.
--                      Metadata-driven (any table with a Tenant_ID column) so it auto-covers
--                      new tables. Full tenant offboarding / test cleanup / DSAR erasure.
--                      NEVER touches the -1 sentinel rows or other tenants. NOTE: tables that
--                      scope by a DIFFERENT key (e.g. Security.Clients by Client_ID) or have
--                      no Tenant_ID column (e.g. Audit.Process_Execution_Log run logs) are not
--                      covered -- purge those separately if required.
--  Params           :  @Tenant_ID  the tenant to purge (required; -1 is refused)
--                      @Dry_Run    1 = report per-table row counts WITHOUT deleting (default 0)
--  To Run           :  EXEC Audit.usp_Delete_All_Tenant @Tenant_ID = 15;              -- delete
--                      EXEC Audit.usp_Delete_All_Tenant @Tenant_ID = 15, @Dry_Run = 1; -- preview
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Audit].[usp_Delete_All_Tenant]
GO
CREATE PROCEDURE [Audit].[usp_Delete_All_Tenant]
(
      @Tenant_ID INT
    , @Dry_Run   BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;

    -- ── Safety guards ──────────────────────────────────────────────────────────
    IF @Tenant_ID IS NULL
        THROW 500030, 'usp_Delete_All_Tenant:: @Tenant_ID is required.', 1;
    IF @Tenant_ID = -1
        THROW 500031, 'usp_Delete_All_Tenant:: refusing to delete the -1 sentinel tenant.', 1;

    -- Build the statement set from metadata: any table with a Tenant_ID column, in EVERY schema
    -- (Bronze/Silver/Gold data + Audit.Tenants + Config/Input/Security per-tenant rows).
    -- STRING_AGG over INFORMATION_SCHEMA (a scalar assign) avoids SELECT INTO #temp FROM catalog
    -- views, which Fabric rejects ("not supported in distributed processing mode"); cursors
    -- aren't available either. Deleting a real tenant never hits the Gold -1 sentinel rows.
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
        WHERE c.COLUMN_NAME = 'Tenant_ID';

        IF @sql IS NULL THROW 500032, 'usp_Delete_All_Tenant:: no tenant-bearing tables found.', 1;
        SET @sql = N'SELECT Table_Name, Rows_Affected FROM (' + @sql + N') x WHERE Rows_Affected > 0 ORDER BY Table_Name;';
        EXEC sp_executesql @sql;
    END
    ELSE
    BEGIN
        -- 1) medallion DATA rows -- delegate to the shared clear (single data-row list, no drift).
        EXEC Audit.usp_Clear_Tenant_Data @Tenant_ID = @Tenant_ID, @Dry_Run = 0;

        -- 2) identity/config rows -- every tenant-bearing table OUTSIDE the medallion (Audit.Tenants,
        --    Config.*, Input.*, Security.* ...). NULL is fine (no config table may carry Tenant_ID).
        SELECT @sql = STRING_AGG(CAST(
            'DELETE FROM [' + c.TABLE_SCHEMA + '].[' + c.TABLE_NAME + '] WHERE Tenant_ID = ' + @tid + ';'
            AS NVARCHAR(MAX)), CHAR(10))
        FROM INFORMATION_SCHEMA.COLUMNS c
        JOIN INFORMATION_SCHEMA.TABLES  t
          ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME AND t.TABLE_TYPE = 'BASE TABLE'
        WHERE c.COLUMN_NAME = 'Tenant_ID'
          AND c.TABLE_SCHEMA NOT IN ('Bronze', 'Silver', 'Gold');

        IF @sql IS NOT NULL EXEC sp_executesql @sql;
        SELECT @Tenant_ID AS Tenant_ID, 'DELETED' AS Mode;
    END
END
GO
