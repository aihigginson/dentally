-- V157: wire the new targets chain into the build DAG, and unwire the retired one.
--
-- ==> THE DAG IS WAREHOUSE METADATA, NOT A FABRIC ITEM. <== Audit.Process_Config and
-- Audit.Process_Dependency are tables in WH_Dentally, so the Fabric deployment pipeline does not
-- promote them. Orchestrate_Build reads them -- the notebook names no procedure at all -- so
-- promoting every notebook, pipeline and report leaves the DAG exactly as it was.
--
-- Measured on prod after "Fabric is up to date":
--
--     GOLD_AGG_DAILY_TARGETS    Gold.usp_Load_Fact_Daily_Targets     STILL WIRED IN, 2 live edges
--     GOLD_FACT_NODE_TARGETS                                         ABSENT
--     GOLD_AGG_PERIOD_TARGETS                                        ABSENT
--
-- So tonight's build would have run the RETIRED loader and never built the new chain at all:
-- Gold.Fact_Node_Targets and Gold.Aggregate_Period_Targets would have gone stale from the moment
-- the release finished, and nothing would have said so -- the reports would simply have kept
-- showing the figures from the last hand-run. That is the failure this migration prevents, and it
-- is why the retired objects must NOT be dropped before the DAG is fixed.
--
-- ==> ORDER MATTERS AND IS COPIED FROM DEV, NOT INVENTED. <==
--
--     GOLD_DIM_DATE           -> GOLD_FACT_NODE_TARGETS    level 5   the calendar first
--     META_SYNC_INPUT         -> GOLD_FACT_NODE_TARGETS    level 5   and the AppDB copy first
--     GOLD_AGG_DATE_GROUPING  -> GOLD_AGG_PERIOD_TARGETS   level 6   the period spine
--     GOLD_FACT_NODE_TARGETS  -> GOLD_AGG_PERIOD_TARGETS   level 6   then apportion it
--
-- The two level-5 edges are the whole point of the node loader's correctness: it reads
-- Input.Client_Region/Area/Site_Area, which META_SYNC_INPUT rebuilds, and it stamps a Selection
-- that the period loader then resolves against the calendar. Running it before the sync reads the
-- previous generation of the hierarchy.
--
-- All three prerequisite codes were confirmed present on prod before writing this.
--
-- Idempotent: every insert is guarded and the deletes match nothing on a second run.

-- ---- 1. the two processes ---------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM Audit.Process_Config WHERE Process_Code = 'GOLD_FACT_NODE_TARGETS')
    INSERT INTO Audit.Process_Config
        (Process_Code, Process_Name, Process_Desc, Process_Parameters,
         Process_Category_Code, Process_Type_Code)
    VALUES ('GOLD_FACT_NODE_TARGETS', 'Gold.usp_Load_Fact_Node_Targets',
            'Explode Input.Targets across every node of every client hierarchy -- quantities roll up, rates roll down, an entered figure always wins. Also publishes Gold.Dim_Hierarchy_Node, the selection-to-sites bridge the app and the period loader both read.',
            '@Mode = ''LIVE'', @Logging = 1', 'GOLD_AGG', 'PROCEDURE');
GO

IF NOT EXISTS (SELECT 1 FROM Audit.Process_Config WHERE Process_Code = 'GOLD_AGG_PERIOD_TARGETS')
    INSERT INTO Audit.Process_Config
        (Process_Code, Process_Name, Process_Desc, Process_Parameters,
         Process_Category_Code, Process_Type_Code)
    VALUES ('GOLD_AGG_PERIOD_TARGETS', 'Gold.usp_Load_Aggregate_Period_Targets',
            'Rebuild Gold.Aggregate_Period_Targets -- the target in force for each (Selection, Role, Metric, Date_Grouping), apportioned per working day so a report reads one row instead of re-aggregating. Reads Gold.Fact_Node_Targets, NOT the retired daily fact.',
            '@Mode = ''LIVE'', @Logging = 1', 'GOLD_AGG', 'PROCEDURE');
GO

-- ---- 2. the edges, copied from dev ------------------------------------------
IF NOT EXISTS (SELECT 1 FROM Audit.Process_Dependency
               WHERE Prev_Process_Code = 'GOLD_DIM_DATE' AND Next_Process_Code = 'GOLD_FACT_NODE_TARGETS')
    INSERT INTO Audit.Process_Dependency
        (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
    VALUES ('GOLD_DIM_DATE', 'GOLD_FACT_NODE_TARGETS', 'DATA', 5, 1);

IF NOT EXISTS (SELECT 1 FROM Audit.Process_Dependency
               WHERE Prev_Process_Code = 'META_SYNC_INPUT' AND Next_Process_Code = 'GOLD_FACT_NODE_TARGETS')
    INSERT INTO Audit.Process_Dependency
        (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
    VALUES ('META_SYNC_INPUT', 'GOLD_FACT_NODE_TARGETS', 'DATA', 5, 1);

IF NOT EXISTS (SELECT 1 FROM Audit.Process_Dependency
               WHERE Prev_Process_Code = 'GOLD_AGG_DATE_GROUPING' AND Next_Process_Code = 'GOLD_AGG_PERIOD_TARGETS')
    INSERT INTO Audit.Process_Dependency
        (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
    VALUES ('GOLD_AGG_DATE_GROUPING', 'GOLD_AGG_PERIOD_TARGETS', 'DATA', 6, 1);

IF NOT EXISTS (SELECT 1 FROM Audit.Process_Dependency
               WHERE Prev_Process_Code = 'GOLD_FACT_NODE_TARGETS' AND Next_Process_Code = 'GOLD_AGG_PERIOD_TARGETS')
    INSERT INTO Audit.Process_Dependency
        (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
    VALUES ('GOLD_FACT_NODE_TARGETS', 'GOLD_AGG_PERIOD_TARGETS', 'DATA', 6, 1);
GO

-- ---- 3. unwire the retired loader -------------------------------------------
-- The edges go first: a Process_Config row with no edges is inert, but an edge pointing at a
-- missing process is what a DAG walker trips over.
DELETE FROM Audit.Process_Dependency
WHERE  Prev_Process_Code = 'GOLD_AGG_DAILY_TARGETS' OR Next_Process_Code = 'GOLD_AGG_DAILY_TARGETS';

DELETE FROM Audit.Process_Config WHERE Process_Code = 'GOLD_AGG_DAILY_TARGETS';
GO

-- ---- 4. prove it, rather than assume it -------------------------------------
SELECT c.Process_Code, c.Process_Name,
       (SELECT COUNT(*) FROM Audit.Process_Dependency d
        WHERE d.Next_Process_Code = c.Process_Code AND d.Is_Active = 1) AS waits_on,
       (SELECT COUNT(*) FROM Audit.Process_Dependency d
        WHERE d.Prev_Process_Code = c.Process_Code AND d.Is_Active = 1) AS feeds
FROM   Audit.Process_Config c
WHERE  c.Process_Name LIKE '%Target%' ORDER BY c.Process_Name;

-- The retired loader must be gone from both tables, and no edge may dangle.
SELECT 'retired loader still referenced (must be 0)' AS check_, COUNT(*) AS rows_
FROM   Audit.Process_Dependency
WHERE  Prev_Process_Code = 'GOLD_AGG_DAILY_TARGETS' OR Next_Process_Code = 'GOLD_AGG_DAILY_TARGETS';

SELECT 'edges pointing at a process that does not exist (must be 0)' AS check_, COUNT(*) AS rows_
FROM   Audit.Process_Dependency d
WHERE  NOT EXISTS (SELECT 1 FROM Audit.Process_Config c WHERE c.Process_Code = d.Prev_Process_Code)
   OR  NOT EXISTS (SELECT 1 FROM Audit.Process_Config c WHERE c.Process_Code = d.Next_Process_Code);
GO
