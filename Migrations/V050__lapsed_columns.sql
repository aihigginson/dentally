-- ===========================================================================
-- V050  lapsed_columns
-- ---------------------------------------------------------------------------
-- Adds Lapsed_Type + fk_Date_Lapsed to Gold.Dim_Patients. ALTER in place (not
-- drop/create) so the surrogate keys the facts point at are preserved. Populated
-- by Gold.usp_Load_Dim_Patients:
--   Type A "Set as inactive"        = Active = 0            (lapse date = updated_at)
--   Type B "Calculated as inactive" = Active but last appt > 730d ago AND no future
--                                     appointment booked    (lapse date = last appt + 730)
-- fk_Date_Lapsed resolves that lapse date to Dim_Date so Lapsed slices by the period
-- it fell in. Fact_Metric_Actuals then materialises the flow cohorts
-- (lapsed_deactivated / lapsed_calculated) plus the lapsed_patients total.
-- Guarded + forward-only. NB: Fabric Warehouse is VARCHAR-only (no NVARCHAR).
-- ===========================================================================

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Dim_Patients') AND name = 'Lapsed_Type')
    ALTER TABLE Gold.Dim_Patients ADD [Lapsed_Type] VARCHAR(30) NULL;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Gold.Dim_Patients') AND name = 'fk_Date_Lapsed')
    ALTER TABLE Gold.Dim_Patients ADD [fk_Date_Lapsed] BIGINT NULL;
