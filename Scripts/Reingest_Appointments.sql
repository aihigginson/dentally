-- =====================================================================
-- Reingest_Appointments.sql  --  full appointments re-pull for a tenant (dev + prod patch)
-- =====================================================================
-- WHERE THIS RUNS: the WAREHOUSE (WH_Dentally). Bronze.Appointments is a warehouse table, and the
-- ingest derives its incremental start as MAX(Bronze.Appointments.Updated_At) WHERE Tenant_ID = ?
-- (build_Ingest_Dentally.py bronze_watermark). You do NOT touch the lakehouse init_stage_*/stage_*
-- tables -- the ingest overwrites those (replaceWhere tenant_id=...) on its next run.
--
-- WHY: the original onboarding pull deliberately EXCLUDED cancelled appointments, so their real
-- (GUID) cancellation reasons never landed and the old int cast dropped them anyway. After V108 the
-- Bronze load is shape-correct; a cold re-pull now captures the cancelled rows + reasons.
--
-- STRATEGY -- per-tenant DELETE, NOT TRUNCATE:
-- The Bronze watermark is per-tenant (WHERE Tenant_ID = ?). Deleting just one tenant's rows resets
-- ONLY that tenant's watermark, so the next ingest re-pulls that tenant alone. TRUNCATE would wipe
-- every tenant and force a full (rate-limited) re-pull of all of them -- avoid it unless that's the
-- intent. Because Bronze appointments then has no rows for the tenant, the ingest cold-pulls
-- (appointments tiles by start_time from history_floor 2021, not updated_after) = the full history
-- incl cancelled.
--
-- PRECONDITION: V106 + V107 + V108 deployed to this environment. Verify:
--   SELECT DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='Bronze'
--     AND TABLE_NAME='Appointments' AND COLUMN_NAME='Appointment_Cancellation_Reason_ID'; -- 'varchar'
--
-- RUNBOOK (per tenant -- repeat @TenantId for each tenant you're patching):
--   1. (baseline)  SELECT State, COUNT(*) FROM Bronze.Appointments WHERE Tenant_ID=@TenantId GROUP BY State;
--   2. Run the DELETE below (set @TenantId).
--   3. Trigger build_Ingest_Dentally with only_tenant = '<TenantId>' (full=False; the empty Bronze
--      watermark makes appointments cold-pull). Heavier than a normal delta; mind the rate window.
--   4. Let Silver -> Gold -> aggregates run, then refresh the model.
--
-- VERIFY (after ingest + build):
--   SELECT State, COUNT(*) FROM Bronze.Appointments WHERE Tenant_ID=@TenantId GROUP BY State;  -- 'Cancelled' present
--   SELECT COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID=@TenantId AND fk_Cancellation_Reason<>-1;  -- >> 0
--   SELECT dcr.Reason, COUNT(*) FROM Gold.Fact_Appointments f
--     JOIN Gold.Dim_Cancellation_Reasons dcr ON dcr.pk_Cancellation_Reason=f.fk_Cancellation_Reason
--    WHERE f.Tenant_ID=@TenantId AND f.fk_Cancellation_Reason<>-1 GROUP BY dcr.Reason ORDER BY 2 DESC;
--
-- Destructive for the chosen tenant until the ingest completes (appointment-derived facts stale in
-- that window). Run at a quiet time.
-- =====================================================================

DECLARE @TenantId INT = 100;   -- <-- set the tenant to re-pull (100 = Maple)

DELETE FROM Bronze.Appointments WHERE Tenant_ID = @TenantId;
GO
