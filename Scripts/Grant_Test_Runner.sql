-- ===========================================================================
-- Grant_Test_Runner.sql
-- ---------------------------------------------------------------------------
-- One-time, run by an ADMIN (you), connected to WH_Dentally, to give the
-- "Test Runner" service principal least-privilege access for Run_Tests.ps1:
--   - own the Test schema (create/alter/drop/select/insert/exec within it)
--   - read Bronze / Silver / Gold (the metric SQL queries these)
--
-- SP: 25da192e-d009-471b-9122-5650ba76d592  (analytically.info tenant)
--
-- SIMPLER ALTERNATIVE (do this FIRST): in Fabric, add the SP to the workspace
-- with the Member (or Contributor) role. That alone grants the warehouse the
-- read+write/DDL the runner needs, and you can skip this script entirely. Use
-- this script only if you want to scope the SP down to read-only on the data
-- layers + ownership of just the Test schema.
--
-- NOTE: replace <SP_DISPLAY_NAME> with the EXACT app-registration display name
-- of the service principal (CREATE USER ... FROM EXTERNAL PROVIDER resolves by
-- name). If CREATE USER errors, fall back to the workspace-role approach above.
-- ===========================================================================

-- Pre-create the Test schema as admin so the SP never needs CREATE SCHEMA.
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Test')
    EXEC('CREATE SCHEMA [Test]');
GO

-- Create the SP as a database user (no broad workspace role required).
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '<SP_DISPLAY_NAME>')
    CREATE USER [<SP_DISPLAY_NAME>] FROM EXTERNAL PROVIDER;
GO

-- Read access to the source layers the metrics query.
GRANT SELECT ON SCHEMA::Bronze TO [<SP_DISPLAY_NAME>];
GRANT SELECT ON SCHEMA::Silver TO [<SP_DISPLAY_NAME>];
GRANT SELECT ON SCHEMA::Gold   TO [<SP_DISPLAY_NAME>];
GO

-- Full control of the Test schema (select/insert/delete/alter/drop/execute on
-- everything in it) plus the ability to create new tables/procs there.
GRANT CONTROL ON SCHEMA::Test TO [<SP_DISPLAY_NAME>];
GRANT CREATE TABLE     TO [<SP_DISPLAY_NAME>];
GRANT CREATE PROCEDURE TO [<SP_DISPLAY_NAME>];
GO
