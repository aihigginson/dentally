-- =============================================================================
-- Audit.Process_Config / Process_Dependency -- register GOLD_FACT_NODE_TARGETS
-- =============================================================================
-- Re-runnable: every statement is NOT EXISTS guarded, because these two tables carry the whole
-- build's orchestration and a release must never duplicate a row into them.
--
-- ==> AND NOTHING READS IT BUT THE PERIOD TARGETS. <== It used to feed Fact_Daily_Targets,
-- the EXPLODED grid now, not Input.Targets, so an un-run explosion means the daily apportionment
-- silently works from the previous night's nodes -- or, the first time, from nothing at all.
-- Registered at dependency level 5 against the same predecessors the daily targets already wait
-- for, with the daily targets then depending on THIS at level 6.
--
-- ==> AND WHILE REGISTERING THIS: GOLD_AGG_PERIOD_TARGETS WAS NEVER REGISTERED ON DEV. <==
-- Audit.Process_Config.Period_Targets.Data.sql exists in this folder and had never been applied
-- here, so Gold.usp_Load_Aggregate_Period_Targets last ran on 18/10/2026 and every target entered
-- since had not reached a single report. Nothing errored; the aggregate simply sat there. That
-- file is applied alongside this one -- a registration file that exists but has not been run is
-- indistinguishable, from the outside, from a job that is quietly broken.
-- =============================================================================

IF NOT EXISTS (SELECT 1 FROM [Audit].[Process_Config] WHERE Process_Code = 'GOLD_FACT_NODE_TARGETS')
    INSERT INTO [Audit].[Process_Config]
        (Process_Code, Process_Name, Process_Desc, Process_Parameters, Process_Category_Code, Process_Type_Code)
    VALUES
        ('GOLD_FACT_NODE_TARGETS',
         'Gold.usp_Load_Fact_Node_Targets',
         'Explode Input.Targets across every node of every client hierarchy -- quantities roll up, rates roll down, an entered figure always wins.',
         '@Mode = ''LIVE'', @Logging = 1',
         'GOLD_AGG', 'PROCEDURE');
GO

-- The explosion waits for the same things the daily targets used to wait for directly.
INSERT INTO [Audit].[Process_Dependency]
    (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
SELECT v.prev, 'GOLD_FACT_NODE_TARGETS', 'DATA', 5, 1
FROM  (VALUES ('GOLD_DIM_DATE'), ('GOLD_FACT_CONTRACTS')) AS v(prev)
WHERE NOT EXISTS (SELECT 1 FROM [Audit].[Process_Dependency] d
                  WHERE d.Prev_Process_Code = v.prev
                    AND d.Next_Process_Code = 'GOLD_FACT_NODE_TARGETS');
GO

-- ...and the daily targets now wait for the explosion. Level 6: a node's level is the MAX of its
-- dependency levels, so leaving this at 5 would put it level with the thing it consumes and
-- nothing would guarantee the order.
INSERT INTO [Audit].[Process_Dependency]
    (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
SELECT 'GOLD_FACT_NODE_TARGETS', 'GOLD_AGG_PERIOD_TARGETS', 'DATA', 6, 1
WHERE NOT EXISTS (SELECT 1 FROM [Audit].[Process_Dependency] d
                  WHERE d.Prev_Process_Code = 'GOLD_FACT_NODE_TARGETS'
                    AND d.Next_Process_Code = 'GOLD_AGG_PERIOD_TARGETS');
GO

-- ==> THE GRID IS BUILT FROM DATA THE APPDB SYNC REWRITES. <== Input.Targets and the whole
-- Input.Client_* hierarchy are owned by the AppDB and rebuilt by Meta.usp_Sync_Input_From_AppDB,
-- which DELETEs and reloads them. The nightly order is already right by category -- the sync is
-- SILVER, this is GOLD_AGG -- but a TARGETED rerun (Audit.usp_Run_Downstream from the sync)
-- stopped short of the target loaders without this edge, so entering a target and rerunning the
-- sync appeared to do nothing.
INSERT INTO Audit.Process_Dependency (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
SELECT 'META_SYNC_INPUT', 'GOLD_FACT_NODE_TARGETS', 'DATA', 5, 1
WHERE NOT EXISTS (SELECT 1 FROM Audit.Process_Dependency d
                  WHERE d.Prev_Process_Code = 'META_SYNC_INPUT'
                    AND d.Next_Process_Code = 'GOLD_FACT_NODE_TARGETS');
