-- V158: drop the retired daily-targets chain.
--
-- ==> LAST, AND ONLY AFTER EVERYTHING THAT COULD NEED IT. <== Gold.Fact_Daily_Targets was the only
-- thing that could re-derive the old figures, so it outlived the release on purpose:
--
--   * it is what the step 10 reconcile was re-derived FROM, as of the day it ran -- comparing the
--     new aggregate against a snapshot built on a different day reported 16 false disagreements,
--     and only summing this fact over each grouping's own dates settled it;
--   * the owner has since confirmed Maple's reports read correctly;
--   * V157 rewired the build DAG, so the new chain actually runs tonight. Dropping the loader
--     before that would have left prod running a process that no longer exists.
--
-- ==> WHAT STILL READS IT: ONE VIEW, AND NOTHING ELSE. <== Checked every stored module and the
-- dependency tables. PBI.[_Daily Targets] is the only reference, and it is NOT in the semantic
-- model -- prod's model has 56 tables and that is not one of them, verified against the model
-- definition rather than assumed. A warehouse guard cannot see a model, so that check had to be
-- made on the model itself.
--
-- The view goes FIRST: a view over a dropped table is not an error until something queries it, and
-- a broken view that nobody notices is worse than a missing one.
--
-- ==> A SNAPSHOT, BECAUSE IT COSTS NOTHING. <== 87,435 rows copied to Backup before the drop. The
-- fact is rebuildable from Input.Targets in principle, but "in principle" is doing a lot of work in
-- that sentence and the copy is free.
--
-- Idempotent: guarded throughout.

IF SCHEMA_ID('Backup') IS NULL EXEC('CREATE SCHEMA [Backup]');
GO

IF OBJECT_ID('Gold.Fact_Daily_Targets') IS NOT NULL
   AND OBJECT_ID('Backup.Fact_Daily_Targets__retired') IS NULL
    EXEC('SELECT * INTO [Backup].[Fact_Daily_Targets__retired] FROM [Gold].[Fact_Daily_Targets]');
GO

IF OBJECT_ID('PBI.[_Daily Targets]') IS NOT NULL
    DROP VIEW PBI.[_Daily Targets];
GO

IF OBJECT_ID('Gold.usp_Load_Fact_Daily_Targets') IS NOT NULL
    DROP PROCEDURE Gold.usp_Load_Fact_Daily_Targets;
GO

IF OBJECT_ID('Gold.Fact_Daily_Targets') IS NOT NULL
    DROP TABLE Gold.Fact_Daily_Targets;
GO

-- ---- prove it, rather than assume it ---------------------------------------
SELECT 'Gold.Fact_Daily_Targets'          AS obj, CASE WHEN OBJECT_ID('Gold.Fact_Daily_Targets') IS NULL THEN 'dropped' ELSE 'STILL THERE' END AS state
UNION ALL SELECT 'Gold.usp_Load_Fact_Daily_Targets', CASE WHEN OBJECT_ID('Gold.usp_Load_Fact_Daily_Targets') IS NULL THEN 'dropped' ELSE 'STILL THERE' END
UNION ALL SELECT 'PBI.[_Daily Targets]',             CASE WHEN OBJECT_ID('PBI.[_Daily Targets]') IS NULL THEN 'dropped' ELSE 'STILL THERE' END
UNION ALL SELECT 'Backup.Fact_Daily_Targets__retired', CASE WHEN OBJECT_ID('Backup.Fact_Daily_Targets__retired') IS NULL THEN 'MISSING' ELSE 'kept' END;

-- Nothing may still name it. A module that does would fail on its next run, not now.
SELECT 'modules still naming it (must be 0)' AS check_, COUNT(*) AS n
FROM   sys.sql_modules m
WHERE  m.definition LIKE '%Fact_Daily_Targets%';

-- And the replacement must actually be holding data, or this drop removed the only copy of
-- something nothing else is producing.
SELECT 'Gold.Fact_Node_Targets'       AS replacement, COUNT(*) AS rows_ FROM Gold.Fact_Node_Targets
UNION ALL SELECT 'Gold.Aggregate_Period_Targets', COUNT(*) FROM Gold.Aggregate_Period_Targets;
GO
