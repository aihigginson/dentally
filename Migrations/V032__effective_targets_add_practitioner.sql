-- V032 -- add fk_Practitioner to Gold.Fact_Effective_Targets.
-- The load proc DROP/CREATEs the table with the full schema, but Fabric validates
-- the proc's INSERT column list against the LIVE table at CREATE PROCEDURE time
-- (eager validation). So ensure the column exists before the proc is deployed.
-- Idempotent: skipped if already present.
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('Gold.Fact_Effective_Targets') AND name = 'fk_Practitioner'
)
    ALTER TABLE [Gold].[Fact_Effective_Targets] ADD [fk_Practitioner] BIGINT;
