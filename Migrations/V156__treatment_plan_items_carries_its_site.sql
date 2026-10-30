-- V156: Gold.Fact_Treatment_Plan_Items gains fk_Practice_Site, by ALTER.
--
-- ==> THE SEMANTIC MODEL IS ONE ARTIFACT, SO PROMOTING IT BRINGS EVERY TABLE'S EXPECTATIONS. <==
-- The targets rework's stored procedures genuinely do not depend on the fk_Practice_Site work --
-- checked, and true. But that is not the whole dependency: the pipeline promotes PBI Dentally as a
-- single item, and the dev model's _Treatment Plan Items and three site-grained aggregates all
-- expect the column. Deploying the model to prod therefore failed its first refresh with
--
--     The 'fk Practice Site' column does not exist in the rowset.
--
-- So the fk_Practice_Site rename is on this release's critical path whether or not the targets code
-- needed it. Concluding "the targets release stands alone" from the proc-level check was wrong.
--
-- ==> ALTER, NOT DROP/CREATE. <== Fabric/Gold.Fact_Treatment_Plan_Items.Table.sql opens with
-- DROP TABLE IF EXISTS, as every fact DDL in this repo does. Deploying that file to prod would
-- delete 265,299 rows and force a full re-ingest. The column is added here instead.
--
-- NULLABLE, matching dev, and for a reason: it is resolved from the practitioner's site
-- (dpr.Site_ID) exactly as the parent fact does, and a plan item whose practitioner has no site
-- resolves to nothing. A NOT NULL column would have to invent a value, and -1 is the fk that hides
-- under "All" and kills under a selection.
--
-- ==> ADDING IT IS NOT ENOUGH. <== Gold.Fact_Treatment_Plan_Items is loaded by a HASH-GATED MERGE:
-- an unchanged source row is skipped, so every existing row would keep a NULL site forever. The
-- loader's watermark has to be wound back for one full pass afterwards -- on dev that was
-- 2000-01-01 and 408,039 rows updated. See the runbook; this migration only makes the column exist.
--
-- Idempotent: guarded, so a re-run adds nothing.

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Gold' AND TABLE_NAME = 'Fact_Treatment_Plan_Items'
                 AND COLUMN_NAME = 'fk_Practice_Site')
    ALTER TABLE [Gold].[Fact_Treatment_Plan_Items] ADD [fk_Practice_Site] BIGINT NULL;
GO

-- ---- prove it, rather than assume it ---------------------------------------
SELECT 'column present' AS check_, COUNT(*) AS n
FROM   INFORMATION_SCHEMA.COLUMNS
WHERE  TABLE_SCHEMA = 'Gold' AND TABLE_NAME = 'Fact_Treatment_Plan_Items'
  AND  COLUMN_NAME = 'fk_Practice_Site';

-- Still NULL everywhere at this point, and that is expected: the hash-gated loader has not been
-- re-run yet. A non-zero "resolved" here before the full pass would mean something else wrote it.
SELECT 'rows' AS check_, COUNT(*) AS rows_,
       SUM(CASE WHEN fk_Practice_Site IS NOT NULL THEN 1 ELSE 0 END) AS resolved
FROM   [Gold].[Fact_Treatment_Plan_Items];
GO
