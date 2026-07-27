-- =====================================================================
-- V112 -- Rename aggregate Rebooked_Cancellations -> Cancellations_Rebooked (display preference).
-- =====================================================================
-- V111 added the column empty; it populates on aggregate reload, so dropping the old name and
-- adding the new is safe (no data a reload doesn't restore). MIGRATE precedes the aggregate
-- load-SP redeploy, which now references the new name (Fabric validates columns at CREATE time).
-- =====================================================================

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('Gold.Aggregate_Site_Patient_Practitioner_Daily') AND name = 'Rebooked_Cancellations')
    ALTER TABLE Gold.Aggregate_Site_Patient_Practitioner_Daily DROP COLUMN Rebooked_Cancellations;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Gold.Aggregate_Site_Patient_Practitioner_Daily') AND name = 'Cancellations_Rebooked')
    ALTER TABLE Gold.Aggregate_Site_Patient_Practitioner_Daily ADD Cancellations_Rebooked INT NULL;
GO
