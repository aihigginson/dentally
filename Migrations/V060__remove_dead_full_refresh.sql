-- =============================================================================
-- V060 -- remove dead code left over from the @Full_Refresh strip
-- =============================================================================
-- Drops the two live objects that the strip made obsolete:
--   * Audit.usp_Load_Bronze  -- only ever called by the defunct Orchestrate_Bronze notebook;
--                               the live nightly (Orchestrate_Build) fires each Bronze job via
--                               Audit.ETL_Run_Process from the metadata DAG instead.
--   * Audit.Tenants.Full_Refresh column -- only read/written by that same defunct notebook.
--                               Live tenant scope is Is_Active; real-Dentally delta is driven by
--                               updated_after/history_floor in Ingest_Dentally, not this column.
-- ALTER ... DROP COLUMN (not a table recreate) so live tenant state (KV mapping, Last_Loaded_At)
-- is preserved. Idempotent-guarded.
-- =============================================================================

DROP PROCEDURE IF EXISTS [Audit].[usp_Load_Bronze];
GO

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('Audit.Tenants') AND name = 'Full_Refresh')
    ALTER TABLE [Audit].[Tenants] DROP COLUMN [Full_Refresh];
GO
