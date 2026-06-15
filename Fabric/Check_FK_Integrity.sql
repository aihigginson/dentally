-- ============================================================
-- Check_FK_Integrity.sql
-- Run after any build change to pinpoint why the embedded
-- app may be showing no data.
--
-- RLS filter (applied to every table with a Tenant_ID):
--   [Tenant ID] IN <user's tenants from Application Users>
--   OR [Tenant ID] = -1
--
-- FAILURE MODES THIS CATCHES:
--
--   1. Application Users mapping wrong or missing
--      => USERPRINCIPALNAME() maps to no tenant, only -1
--         rows visible, real Fact rows vanish.
--
--   2. -1 seed row missing from a Dim
--      => a full table rebuild drops the table; seed row only
--         comes back when the load SP runs. Fact rows with
--         fk_* = -1 lose their Dim match.
--
--   3. Dim completely empty
--      => Dim->Fact relationship filter passes nothing;
--         all Fact rows referencing that Dim disappear.
--
--   4. Fact FK references a Dim PK from the wrong tenant
--      => That Dim row is hidden by RLS in the app but
--         visible in Desktop (no RLS).
-- ============================================================
SET NOCOUNT ON;

-- ===========================================================
-- 1. Application Users UPN -> Tenant mapping
--    Missing UPN = RLS IN {} = only -1 rows visible = no data
-- ===========================================================
PRINT '1. Application Users -> Tenant mapping';

SELECT
    a.User_UPN,
    t.Tenant_ID,
    t.Tenant_Name,
    CASE WHEN t.Tenant_ID IS NULL THEN 'WARN: Client_ID not in Audit.Tenants'
         ELSE 'OK'
    END AS Status
FROM Security.Application_Users a
LEFT JOIN Audit.Tenants t ON t.Client_ID = a.Client_ID
ORDER BY a.User_UPN;

-- ===========================================================
-- 2. Dim seed row (-1) and real row check
--    Seed_Row = 0  => fk_*=-1 Fact rows lose their Dim match
--    Real_Rows = 0 => Dim load SP has not run
-- ===========================================================
PRINT '';
PRINT '2. Dim table population';

SELECT
    Dim_Table,
    SUM(CASE WHEN Tenant_ID = -1 THEN 1 ELSE 0 END) AS Seed_Row,
    SUM(CASE WHEN Tenant_ID  > 0 THEN 1 ELSE 0 END) AS Real_Rows,
    CASE
        WHEN SUM(CASE WHEN Tenant_ID = -1 THEN 1 ELSE 0 END) = 0
             AND SUM(CASE WHEN Tenant_ID > 0 THEN 1 ELSE 0 END) = 0
             THEN 'EMPTY - load SP has not run'
        WHEN SUM(CASE WHEN Tenant_ID = -1 THEN 1 ELSE 0 END) = 0
             THEN 'WARN - seed row (-1) missing'
        ELSE 'OK'
    END AS Status
FROM (
    SELECT 'Dim_Payment_Plans'  AS Dim_Table, Tenant_ID FROM Gold.Dim_Payment_Plans
    UNION ALL
    SELECT 'Dim_Practice_Sites' AS Dim_Table, Tenant_ID FROM Gold.Dim_Practice_Sites
    UNION ALL
    SELECT 'Dim_Practitioners'  AS Dim_Table, Tenant_ID FROM Gold.Dim_Practitioners
    UNION ALL
    SELECT 'Dim_Users'          AS Dim_Table, Tenant_ID FROM Gold.Dim_Users
    UNION ALL
    SELECT 'Dim_Patients'       AS Dim_Table, Tenant_ID FROM Gold.Dim_Patients
) dims
GROUP BY Dim_Table
ORDER BY Dim_Table;

-- ===========================================================
-- 3. FK cross-tenant integrity (Fact_Appointments)
--    Uses LEFT JOIN: NULL result = FK has no visible Dim match.
--    Non-zero = rows invisible in the app but visible in Desktop.
-- ===========================================================
PRINT '';
PRINT '3. FK cross-tenant integrity (Fact_Appointments)';

SELECT
    fa.Tenant_ID,
    COUNT(*)                                                                          AS Total_Appts,
    SUM(CASE WHEN fa.fk_Patient       <> -1 AND dpat.pk_Patient       IS NULL THEN 1 ELSE 0 END) AS Patient_Mismatch,
    SUM(CASE WHEN fa.fk_Practitioner  <> -1 AND dpr.pk_Practitioner   IS NULL THEN 1 ELSE 0 END) AS Practitioner_Mismatch,
    SUM(CASE WHEN fa.fk_Payment_Plan  <> -1 AND dpp.pk_Payment_Plan   IS NULL THEN 1 ELSE 0 END) AS PaymentPlan_Mismatch,
    SUM(CASE WHEN fa.fk_Practice_Site <> -1 AND dps.pk_Practice_Site  IS NULL THEN 1 ELSE 0 END) AS PracticeSite_Mismatch,
    SUM(CASE WHEN fa.fk_User          <> -1 AND du.pk_User            IS NULL THEN 1 ELSE 0 END) AS User_Mismatch
FROM Gold.Fact_Appointments fa
LEFT JOIN Gold.Dim_Patients      dpat ON dpat.pk_Patient      = fa.fk_Patient
                                     AND (dpat.Tenant_ID = fa.Tenant_ID OR dpat.Tenant_ID = -1)
LEFT JOIN Gold.Dim_Practitioners dpr  ON dpr.pk_Practitioner  = fa.fk_Practitioner
                                     AND (dpr.Tenant_ID  = fa.Tenant_ID OR dpr.Tenant_ID  = -1)
LEFT JOIN Gold.Dim_Payment_Plans dpp  ON dpp.pk_Payment_Plan  = fa.fk_Payment_Plan
                                     AND (dpp.Tenant_ID  = fa.Tenant_ID OR dpp.Tenant_ID  = -1)
LEFT JOIN Gold.Dim_Practice_Sites dps ON dps.pk_Practice_Site = fa.fk_Practice_Site
                                     AND (dps.Tenant_ID  = fa.Tenant_ID OR dps.Tenant_ID  = -1)
LEFT JOIN Gold.Dim_Users          du  ON du.pk_User            = fa.fk_User
                                     AND (du.Tenant_ID   = fa.Tenant_ID OR du.Tenant_ID   = -1)
WHERE fa.Tenant_ID > 0
GROUP BY fa.Tenant_ID
ORDER BY fa.Tenant_ID;

-- ===========================================================
-- 4. Silver vs Gold row counts
--    Diff < 0 = Gold load dropped rows
-- ===========================================================
PRINT '';
PRINT '4. Silver vs Gold row counts';

SELECT
    COALESCE(s.Tenant_ID, g.Tenant_ID)        AS Tenant_ID,
    ISNULL(s.Silver_Appts, 0)                 AS Silver_Appts,
    ISNULL(g.Gold_Appts,   0)                 AS Gold_Appts,
    ISNULL(g.Gold_Appts, 0) - ISNULL(s.Silver_Appts, 0) AS Diff,
    CASE
        WHEN ISNULL(g.Gold_Appts, 0) = 0
             THEN 'EMPTY - Gold load has not run'
        WHEN ISNULL(g.Gold_Appts, 0) < ISNULL(s.Silver_Appts, 0)
             THEN 'WARN - Gold has fewer rows than Silver'
        ELSE 'OK'
    END AS Status
FROM (
    SELECT Tenant_ID, COUNT(*) AS Silver_Appts
    FROM Silver.Appointments
    WHERE Appointment_ID IS NOT NULL
    GROUP BY Tenant_ID
) s
FULL OUTER JOIN (
    SELECT Tenant_ID, COUNT(*) AS Gold_Appts
    FROM Gold.Fact_Appointments
    WHERE Tenant_ID > 0
    GROUP BY Tenant_ID
) g ON g.Tenant_ID = s.Tenant_ID
ORDER BY COALESCE(s.Tenant_ID, g.Tenant_ID);
