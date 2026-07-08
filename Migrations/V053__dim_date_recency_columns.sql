-- ===========================================================================
-- V053  dim_date_recency_columns
-- ---------------------------------------------------------------------------
-- Fabric Warehouse validates a stored-proc body at CREATE time against the LIVE
-- table. Gold.usp_Load_Dim_Date DROP/CREATEs Dim_Date internally (with Recency_Band
-- + Recency_Band_Sort), but CREATE PROCEDURE validates its INSERT against the
-- EXISTING table first -> "Invalid column name 'Recency_Band'". Pre-add the columns
-- so the deploy validates; the SP's own rebuild immediately re-creates them NOT NULL
-- and populated, so NULLABLE here is fine (these ALTER'd columns are transient).
-- Guarded + forward-only.
-- ===========================================================================

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Dim_Date') AND name = 'Recency_Band')
    ALTER TABLE Gold.Dim_Date ADD [Recency_Band] VARCHAR(20) NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Dim_Date') AND name = 'Recency_Band_Sort')
    ALTER TABLE Gold.Dim_Date ADD [Recency_Band_Sort] SMALLINT NULL;
