-- =====================================================================
-- V111 -- Short Notice as a per-appointment date-based flag on the fact;
--         Rebooked_Cancellations on the daily aggregate; drop the reason-based
--         Is_Short_Notice from Dim_Cancellation_Reasons.
-- =====================================================================
-- In-place ALTERs (Gold tables persist -- DROP/CREATE would wipe them). MIGRATE
-- must precede the SP DEPLOYs (Fabric validates columns at CREATE time). After
-- deploy, reload via Orchestrate_Build so the new flag/column populate (Is_Short_Notice
-- is in the Fact change-hash, so every existing appointment UPDATEs once).
-- =====================================================================

-- 1. Fact_Appointments: date-based short-notice flag (cancelled within 1 day of Start_Time)
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Gold.Fact_Appointments') AND name = 'Is_Short_Notice')
    ALTER TABLE Gold.Fact_Appointments ADD Is_Short_Notice BIT NULL;
GO

-- 2. Aggregate: rebooked-cancellation count (cancelled appts with Rebooked_Status = 'Rebooked')
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Gold.Aggregate_Site_Patient_Practitioner_Daily') AND name = 'Rebooked_Cancellations')
    ALTER TABLE Gold.Aggregate_Site_Patient_Practitioner_Daily ADD Rebooked_Cancellations INT NULL;
GO

-- 3. Dim_Cancellation_Reasons: drop the reason-based flag (empty on real data; short notice is
--    now a per-appointment date-based fact flag). SPs are not schema-bound, so the drop is safe
--    ahead of the load-SP redeploy.
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('Gold.Dim_Cancellation_Reasons') AND name = 'Is_Short_Notice')
    ALTER TABLE Gold.Dim_Cancellation_Reasons DROP COLUMN Is_Short_Notice;
GO
