-- V033 -- add Long_Description to Config.Metric_Definitions.
-- Plain-English metric definition for the in-product glossary / help panel.
-- Additive nullable column; the seed (Config.Metric_Definitions.Data.sql) populates it
-- via MERGE. Guarded ALTER so the deploy doesn't DROP/CREATE (and lose) the config table.
-- Idempotent: skipped if already present.
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('Config.Metric_Definitions') AND name = 'Long_Description'
)
    ALTER TABLE [Config].[Metric_Definitions] ADD [Long_Description] VARCHAR(1000) NULL;
