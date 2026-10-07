-- V153: let the ten-minute access sync decide "nothing changed" WITHOUT touching Fabric.
--
-- ==> 4,015 RUNS IN 14 DAYS. EVERY SINGLE ONE A NO-OP. <== Measured on both warehouses:
--
--     DEV   appdb_sync.access   2007 runs   all no-op   6.05s avg
--     PROD  appdb_sync.access   2008 runs   all no-op   5.77s avg
--
-- V199 already stopped this job WRITING when nothing had changed, which was the right fix for the
-- statements it was issuing. What it could not fix is that the job must still OPEN A FABRIC SESSION
-- to find out there is nothing to do, because every piece of state it consults lives in the
-- warehouse: the Input_Stage column map, Input_Stage.Sync_Fingerprint, the previous run's status in
-- Audit.Process_Execution_Log, and the proc sentinel. Four round trips to conclude "no".
--
-- On the capacity those land in 30-second Warehouse Query buckets costing 300-750 CU(s) each, around
-- the clock, on both environments -- including 03:40 on dev, where there are no users at all. The
-- warehouses are 75% of all capacity consumption and only about 9% of that is the nightly build's
-- SQL; this is the bulk of the rest.
--
-- ==> SO THE CHANGE-DETECTION STATE MOVES TO WHERE IT IS FREE. <== AppDB is Azure SQL, billed on
-- provisioned capacity rather than per statement, and the job already connects to it to read the
-- source rows. Mirroring the state here lets the no-op path answer entirely from AppDB and exit
-- without a Fabric connection at all.
--
-- ==> THE WAREHOUSE COPY REMAINS THE AUTHORITY. <== Input_Stage.Sync_Fingerprint is still written
-- on every real sync and is still what proves staging matches source. This table is a CACHE of it,
-- written in the same breath. Anything missing, stale or unparseable here makes the job fall
-- through to the Fabric path, which is the safe direction: the worst case is the behaviour we have
-- today.

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
               WHERE s.name = 'Input' AND t.name = 'Sync_State')
BEGIN
    CREATE TABLE Input.Sync_State (
        -- A source table name, or one of the sentinels below. Not an identity: the key IS the item.
        Item         VARCHAR(64)    NOT NULL,
        Row_Count    INT            NULL,
        Fingerprint  VARCHAR(128)   NULL,
        -- JSON, used only by the '(columns)' sentinel to carry the Input_Stage column map so the
        -- fast path can build the same SELECT the slow path would, without asking Fabric for it.
        Payload      NVARCHAR(MAX)  NULL,
        Updated_At   DATETIME2(3)   NOT NULL,
        CONSTRAINT PK_Sync_State PRIMARY KEY (Item)
    );
END
GO

-- Sentinels, documented here because they are the only rows whose Item is not a table name:
--   '(access proc)'  -- when Meta.usp_Sync_Access_From_AppDB last actually ran; drives the
--                       self-heal window (PROC_MAX_SKIP_MINUTES), so a reasoning error in the skip
--                       logic can never stall the merge for longer than that.
--   '(columns)'      -- Payload = JSON {table: [column, ...]} for Input_Stage, refreshed whenever
--                       the job connects to Fabric. A schema change therefore costs one ordinary
--                       slow run to pick up, which is exactly when it should be picked up.
--   '(last status)'  -- the outcome of the previous access run. A previous failure must force a
--                       real run, or a no-op decision would make a half-written target permanent.

SELECT Item, Row_Count, LEFT(ISNULL(Fingerprint, ''), 16) AS Fingerprint_Head, Updated_At
FROM   Input.Sync_State
ORDER BY Item;
