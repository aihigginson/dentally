-- V108b__reingest_appointments.sql
-- Data backfill for the cancellation_reason_id GUID fix (V108). The original onboarding pull EXCLUDED
-- cancelled appointments and the old int cast dropped their GUID reasons, so existing tenants have
-- cancellations with NO reason. Force a full appointments re-pull for any tenant still in that
-- PRE-FIX state: deleting the tenant's Bronze appointments resets its per-tenant watermark
-- (bronze_watermark = MAX(Updated_At) WHERE Tenant_ID = ?), so the NEXT ingest cold-pulls the full
-- history INCLUDING cancelled appointments + their GUID reasons, through the V108-fixed load.
--
-- GUARDED + IDEMPOTENT: only deletes tenants whose cancellations currently resolve to ZERO reasons.
-- A tenant that already has reasons (already patched, e.g. dev) is skipped -> safe no-op there.
-- MIGRATE = tracked, runs once per environment.
--
-- *** REQUIRES the appointments ingest to run AFTER this deploy *** (build_Ingest_Dentally with the
-- affected tenant(s); the warehouse manifest can't trigger a Fabric notebook). Until it runs, the
-- deleted tenants have no Bronze appointments and appointment-derived facts are stale. Deploy in a
-- window where the ingest + build follow.
DELETE FROM Bronze.Appointments
WHERE Tenant_ID IN (
    SELECT Tenant_ID
    FROM   Bronze.Appointments
    WHERE  State = 'Cancelled'
    GROUP BY Tenant_ID
    HAVING SUM(CASE WHEN Appointment_Cancellation_Reason_ID IS NOT NULL
                     AND Appointment_Cancellation_Reason_ID <> '' THEN 1 ELSE 0 END) = 0
);
GO
