-- =============================================================================
-- Audit.Process_Config / Process_Dependency -- register GOLD_AGG_PERIOD_TARGETS
-- =============================================================================
-- Re-runnable: every statement is NOT EXISTS guarded, because these two tables carry the whole
-- build's orchestration and a release must never duplicate a row into them.
--
-- ==> DEPENDENCY_LEVEL 6, NOT 5, AND THAT IS THE POINT. <== This aggregate reads two OTHER
-- aggregates -- Fact_Daily_Targets and Dim_Date_Grouping -- both of which are themselves level
-- 5. A node's level is the MAX of its dependency levels, so registering these edges at 5 would
-- leave it level 5 too: the same level as the things it consumes, with nothing guaranteeing it
-- runs after them. It would then aggregate the PREVIOUS run's targets, which is wrong in a way
-- that looks completely normal on screen.
--
-- Level 6 already exists for exactly this case (two nodes use it today), so this follows the
-- established shape rather than inventing one.
-- =============================================================================

IF NOT EXISTS (SELECT 1 FROM [Audit].[Process_Config] WHERE Process_Code = 'GOLD_AGG_PERIOD_TARGETS')
INSERT INTO [Audit].[Process_Config]
    (Process_Code, Process_Name, Process_Desc, Process_Parameters, Process_Category_Code, Process_Type_Code)
VALUES
    ('GOLD_AGG_PERIOD_TARGETS',
     'Gold.usp_Load_Aggregate_Period_Targets',
     'Rebuild Gold.Aggregate_Period_Targets -- the target for each (Date_Grouping, Metric, Target_Level), precomputed so the model stops re-aggregating 243k daily rows per tile on every render. The period is always one named grouping, so 1,296 rows answer what the daily fact was being scanned for ~84 times a page. GOLD_AGG: reads Gold.Fact_Daily_Targets + Dim_Date_Grouping + Config.Metric_Definitions.',
     '@Mode = ''LIVE'', @Logging = 1',
     'GOLD_AGG', 'PROCEDURE');
GO

INSERT INTO [Audit].[Process_Dependency]
    (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
SELECT v.prev, 'GOLD_AGG_PERIOD_TARGETS', 'DATA', 6, 1
FROM (VALUES ('GOLD_AGG_DAILY_TARGETS'), ('GOLD_AGG_DATE_GROUPING')) AS v(prev)
WHERE NOT EXISTS (SELECT 1 FROM [Audit].[Process_Dependency] d
                   WHERE d.Prev_Process_Code = v.prev
                     AND d.Next_Process_Code = 'GOLD_AGG_PERIOD_TARGETS');
GO
