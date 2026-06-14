-- ===========================================================================
-- V001  patient_cohort_flags
-- ---------------------------------------------------------------------------
-- Adds the patient-cohort condition flags WITHOUT a DROP/CREATE rebuild, so an
-- existing warehouse keeps its data. The matching full definitions live in the
-- Fabric/Gold.*.Table.sql object files (used for fresh installs); the load SPs
-- (Gold.usp_Load_Fact_Invoice_Items / usp_Load_Dim_Patients) that POPULATE these
-- columns deploy from their own idempotent object scripts and backfill on the
-- next Gold reload.
--
-- Idempotent: each ADD is guarded, so re-applying is a no-op. Forward-only.
-- ===========================================================================

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Invoice_Items') AND name = 'Is_Invoice_Outstanding')
    ALTER TABLE Gold.Fact_Invoice_Items ADD [Is_Invoice_Outstanding] bit NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Fact_Invoice_Items') AND name = 'Is_Discount')
    ALTER TABLE Gold.Fact_Invoice_Items ADD [Is_Discount] bit NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Dim_Patients') AND name = 'Is_Email_Missing')
    ALTER TABLE Gold.Dim_Patients ADD [Is_Email_Missing] bit NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Dim_Patients') AND name = 'Is_Phone_Missing')
    ALTER TABLE Gold.Dim_Patients ADD [Is_Phone_Missing] bit NULL;
GO
