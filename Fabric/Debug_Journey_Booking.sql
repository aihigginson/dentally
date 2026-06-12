-- Debug_Journey_Booking.sql
-- Run each section independently in Fabric SQL editor.
-- Purpose: trace BBYL / Online Booking data through each layer to find where it breaks.
-- ============================================================

-- ── 1. STAGE LAYER ──────────────────────────────────────────
-- Check raw values coming out of the Delta tables.
-- booked_via_api should be '1' or '0' (not 'True'/'False').
-- pending_at should be populated for BBYL rows.

SELECT TOP 20
    booked_via_api,
    pending_at,
    start_time,
    state
FROM stage_appointments
WHERE tenant_id = '11'
  AND booked_via_api IS NOT NULL
  AND booked_via_api <> '0'
ORDER BY NEWID();   -- random sample

-- Expected: booked_via_api = '1', pending_at like '2024-03-15T08:00:00'
-- Bad:      booked_via_api = 'True' (bool serialisation bug still present)

-- ── 2. BRONZE LAYER ─────────────────────────────────────────
-- Check TRY_CAST result. If stage has '1'/'0', Bronze should have 1/0.
-- If Bronze shows 0 for everything, the cast is failing.

SELECT
    SUM(CASE WHEN Booked_Via_API = 1 THEN 1 ELSE 0 END) AS booked_via_api_1,
    SUM(CASE WHEN Booked_Via_API = 0 THEN 1 ELSE 0 END) AS booked_via_api_0,
    SUM(CASE WHEN Booked_Via_API IS NULL THEN 1 ELSE 0 END) AS booked_via_api_null,
    COUNT(*) AS total
FROM Bronze.Appointments
WHERE Tenant_ID = 11;

-- Also spot-check a few rows with Pending_At populated
SELECT TOP 10
    Appointment_ID,
    Booked_Via_API,
    Pending_At,
    Start_Time
FROM Bronze.Appointments
WHERE Tenant_ID = 11
  AND Booked_Via_API = 1
ORDER BY NEWID();

-- ── 3. SILVER LAYER ─────────────────────────────────────────
-- Check Silver.Appointments after the MERGE.

SELECT
    SUM(CASE WHEN Booked_Via_API = 1 THEN 1 ELSE 0 END) AS booked_via_api_1,
    SUM(CASE WHEN Booked_Via_API = 0 THEN 1 ELSE 0 END) AS booked_via_api_0,
    COUNT(*) AS total
FROM Silver.Appointments
WHERE Tenant_ID = 11;

-- Spot-check pending_at and the cast that the Journey SP does
SELECT TOP 10
    Appointment_ID,
    Booked_Via_API,
    Pending_At,
    TRY_CAST(LEFT(NULLIF(TRIM(Pending_At), ''), 23) AS datetime2(3)) AS Pending_DT,
    Start_Time,
    TRY_CAST(LEFT(NULLIF(TRIM(Start_Time), ''), 23) AS datetime2(3))  AS Start_DT
FROM Silver.Appointments
WHERE Tenant_ID = 11
  AND Booked_Via_API = 1
ORDER BY NEWID();

-- ── 4. BBYL DATE MATCH CHECK ────────────────────────────────
-- Manually reproduce the BBYL logic for a sample of booked-via-API rows.
-- Shows whether Pending_DT matches the previous completed appointment date.

WITH appts AS (
    SELECT
        Appointment_ID,
        Patient_ID,
        Booked_Via_API,
        TRY_CAST(LEFT(NULLIF(TRIM(Start_Time),   ''), 23) AS datetime2(3)) AS Start_DT,
        TRY_CAST(LEFT(NULLIF(TRIM(Pending_At),   ''), 23) AS datetime2(3)) AS Pending_DT,
        TRY_CAST(LEFT(NULLIF(TRIM(Completed_At), ''), 23) AS datetime2(3)) AS Completed_DT
    FROM Silver.Appointments
    WHERE Tenant_ID = 11
)
SELECT TOP 20
    a.Appointment_ID,
    a.Patient_ID,
    a.Booked_Via_API,
    CAST(a.Pending_DT   AS DATE)    AS Pending_Date,
    prev.Prev_Date,
    CASE WHEN CAST(a.Pending_DT AS DATE) = prev.Prev_Date THEN 'BBYL MATCH'
         WHEN a.Booked_Via_API = 1                        THEN 'Online (no match)'
         ELSE 'Reception'
    END AS Would_Be_Classified
FROM appts a
OUTER APPLY (
    SELECT TOP 1 CAST(p.Start_DT AS DATE) AS Prev_Date
    FROM appts p
    WHERE p.Patient_ID   = a.Patient_ID
      AND p.Completed_DT IS NOT NULL
      AND p.Start_DT     < a.Start_DT
    ORDER BY p.Start_DT DESC
) prev
WHERE a.Booked_Via_API = 1
ORDER BY NEWID();

-- ── 5. JOURNEY ATTRIBUTES RESULT ────────────────────────────
-- Check what the Journey SP actually produced.

SELECT
    Booking,
    COUNT(*) AS n
FROM Silver.Appointment_Journey_Attributes
WHERE Tenant_ID = 11
GROUP BY Booking
ORDER BY n DESC;

-- If Booking shows only 'New' / 'Reception' / 'Referral' with no BBYL or Online,
-- the issue is upstream (Booked_Via_API = 0 in Silver).

-- Current_State distribution
SELECT
    Current_State,
    COUNT(*) AS n
FROM Silver.Appointment_Journey_Attributes
WHERE Tenant_ID = 11
GROUP BY Current_State
ORDER BY n DESC;
