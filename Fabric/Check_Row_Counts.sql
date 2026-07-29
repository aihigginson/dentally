-- ============================================================
-- Check_Row_Counts.sql
-- Validates row counts across all three medallion layers.
--
-- Section 1  Entity summary  Bronze / Silver / Gold (all tenants)
-- Section 2  Per-tenant detail for key facts
-- Section 3  Silver-derived table checks
-- Section 4  Journey classification breakdown
-- ============================================================
SET NOCOUNT ON;

-- ============================================================
-- 1. Entity summary: Bronze vs Silver vs Gold
--    Gold Dim counts exclude the -1 seed row for a fair comparison.
--    Status: EMPTY = load SP not run | WARN = rows dropped | OK
-- ============================================================
PRINT '1. Entity summary (Bronze / Silver / Gold, all tenants combined)';

SELECT
    src.Entity,
    src.Type,
    src.Bronze,
    src.Silver,
    src.Gold,
    CASE WHEN src.Bronze > 0 AND src.Silver = 0     THEN 'ERROR  Silver empty'
         WHEN src.Silver > src.Bronze                THEN 'WARN   Silver > Bronze'
         WHEN src.Silver < src.Bronze                THEN 'WARN   Silver dropped rows'
         ELSE                                             'OK     Bronze=Silver'
    END AS Bronze_Silver,
    CASE WHEN src.Silver > 0 AND src.Gold = 0       THEN 'ERROR  Gold empty'
         WHEN src.Gold   < src.Silver                THEN 'WARN   Gold dropped rows'
         ELSE                                             'OK     Gold>=Silver'
    END AS Silver_Gold
FROM (

    -- ── Facts ──────────────────────────────────────────────────────────────
    SELECT 'Appointments'          AS Entity, 'Fact' AS Type,
        (SELECT COUNT(*) FROM Bronze.Appointments)        AS Bronze,
        (SELECT COUNT(*) FROM Silver.Appointments)        AS Silver,
        (SELECT COUNT(*) FROM Gold.Fact_Appointments      WHERE Tenant_ID > 0) AS Gold

    UNION ALL SELECT 'Recalls', 'Fact',
        (SELECT COUNT(*) FROM Bronze.Recalls),
        (SELECT COUNT(*) FROM Silver.Recalls),
        (SELECT COUNT(*) FROM Gold.Fact_Recalls           WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Treatment_Appointments', 'Fact',
        (SELECT COUNT(*) FROM Bronze.Treatment_Appointments),
        (SELECT COUNT(*) FROM Silver.Treatment_Appointments),
        (SELECT COUNT(*) FROM Gold.Fact_Treatment_Appointments WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Treatment_Plan_Items', 'Fact',
        (SELECT COUNT(*) FROM Bronze.Treatment_Plan_Items),
        (SELECT COUNT(*) FROM Silver.Treatment_Plan_Items),
        (SELECT COUNT(*) FROM Gold.Fact_Treatment_Plan_Items   WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Invoice_Items', 'Fact',
        (SELECT COUNT(*) FROM Bronze.Invoice_Items),
        (SELECT COUNT(*) FROM Silver.Invoice_Items),
        (SELECT COUNT(*) FROM Gold.Fact_Invoice_Items     WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Practitioner_Diary', 'Fact',
        (SELECT COUNT(*) FROM Bronze.Practitioner_Diary),
        (SELECT COUNT(*) FROM Silver.Practitioner_Diary),
        (SELECT COUNT(*) FROM Gold.Fact_Practitioner_Diaries   WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Contracts', 'Fact',
        (SELECT COUNT(*) FROM Bronze.Contracts),
        (SELECT COUNT(*) FROM Silver.Contracts),
        (SELECT COUNT(*) FROM Gold.Fact_Contracts         WHERE Tenant_ID > 0)

    -- ── Dimensions ─────────────────────────────────────────────────────────
    UNION ALL SELECT 'Patients', 'Dim',
        (SELECT COUNT(*) FROM Bronze.Patients),
        (SELECT COUNT(*) FROM Silver.Patients),
        (SELECT COUNT(*) FROM Gold.Dim_Patients           WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Practitioners', 'Dim',
        (SELECT COUNT(*) FROM Bronze.Practitioners),
        (SELECT COUNT(*) FROM Silver.Practitioners),
        (SELECT COUNT(*) FROM Gold.Dim_Practitioners      WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Sites', 'Dim',
        (SELECT COUNT(*) FROM Bronze.Sites),
        (SELECT COUNT(*) FROM Silver.Sites),
        (SELECT COUNT(*) FROM Gold.Dim_Practice_Sites     WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Users', 'Dim',
        (SELECT COUNT(*) FROM Bronze.Users),
        (SELECT COUNT(*) FROM Silver.Users),
        (SELECT COUNT(*) FROM Gold.Dim_Users              WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Payment_Plans', 'Dim',
        (SELECT COUNT(*) FROM Bronze.Payment_Plans),
        (SELECT COUNT(*) FROM Silver.Payment_Plans),
        (SELECT COUNT(*) FROM Gold.Dim_Payment_Plans      WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Treatment_Plans', 'Dim',
        (SELECT COUNT(*) FROM Bronze.Treatment_Plans),
        (SELECT COUNT(*) FROM Silver.Treatment_Plans),
        (SELECT COUNT(*) FROM Gold.Dim_Treatment_Plans    WHERE Tenant_ID > 0)

    UNION ALL SELECT 'Treatments', 'Dim',
        (SELECT COUNT(*) FROM Bronze.Treatments),
        (SELECT COUNT(*) FROM Silver.Treatments),
        (SELECT COUNT(*) FROM Gold.Dim_Treatments         WHERE Tenant_ID > 0)

) src
ORDER BY src.Type DESC, src.Entity;


-- ============================================================
-- 2. Per-tenant detail: key facts
-- ============================================================
PRINT '';
PRINT '2. Per-tenant detail — key facts';

SELECT
    COALESCE(b.Tenant_ID, s.Tenant_ID, g.Tenant_ID)            AS Tenant_ID,
    'Appointments'                                               AS Entity,
    ISNULL(b.Cnt, 0)                                            AS Bronze,
    ISNULL(s.Cnt, 0)                                            AS Silver,
    ISNULL(g.Cnt, 0)                                            AS Gold,
    CASE WHEN ISNULL(s.Cnt,0) = 0 AND ISNULL(b.Cnt,0) > 0 THEN 'ERROR  Silver empty'
         WHEN ISNULL(s.Cnt,0) < ISNULL(b.Cnt,0)            THEN 'WARN   Silver < Bronze'
         ELSE 'OK' END                                           AS Bronze_Silver,
    CASE WHEN ISNULL(g.Cnt,0) = 0 AND ISNULL(s.Cnt,0) > 0 THEN 'ERROR  Gold empty'
         WHEN ISNULL(g.Cnt,0) < ISNULL(s.Cnt,0)            THEN 'WARN   Gold < Silver'
         ELSE 'OK' END                                           AS Silver_Gold
FROM (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Bronze.Appointments GROUP BY Tenant_ID) b
FULL OUTER JOIN (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Silver.Appointments GROUP BY Tenant_ID) s
    ON s.Tenant_ID = b.Tenant_ID
FULL OUTER JOIN (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Gold.Fact_Appointments WHERE Tenant_ID > 0 GROUP BY Tenant_ID) g
    ON g.Tenant_ID = COALESCE(b.Tenant_ID, s.Tenant_ID)

UNION ALL

SELECT
    COALESCE(b.Tenant_ID, s.Tenant_ID, g.Tenant_ID),
    'Recalls',
    ISNULL(b.Cnt, 0), ISNULL(s.Cnt, 0), ISNULL(g.Cnt, 0),
    CASE WHEN ISNULL(s.Cnt,0) = 0 AND ISNULL(b.Cnt,0) > 0 THEN 'ERROR  Silver empty'
         WHEN ISNULL(s.Cnt,0) < ISNULL(b.Cnt,0)            THEN 'WARN   Silver < Bronze'
         ELSE 'OK' END,
    CASE WHEN ISNULL(g.Cnt,0) = 0 AND ISNULL(s.Cnt,0) > 0 THEN 'ERROR  Gold empty'
         WHEN ISNULL(g.Cnt,0) < ISNULL(s.Cnt,0)            THEN 'WARN   Gold < Silver'
         ELSE 'OK' END
FROM (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Bronze.Recalls GROUP BY Tenant_ID) b
FULL OUTER JOIN (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Silver.Recalls GROUP BY Tenant_ID) s
    ON s.Tenant_ID = b.Tenant_ID
FULL OUTER JOIN (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Gold.Fact_Recalls WHERE Tenant_ID > 0 GROUP BY Tenant_ID) g
    ON g.Tenant_ID = COALESCE(b.Tenant_ID, s.Tenant_ID)

UNION ALL

SELECT
    COALESCE(b.Tenant_ID, s.Tenant_ID, g.Tenant_ID),
    'Patients',
    ISNULL(b.Cnt, 0), ISNULL(s.Cnt, 0), ISNULL(g.Cnt, 0),
    CASE WHEN ISNULL(s.Cnt,0) = 0 AND ISNULL(b.Cnt,0) > 0 THEN 'ERROR  Silver empty'
         WHEN ISNULL(s.Cnt,0) < ISNULL(b.Cnt,0)            THEN 'WARN   Silver < Bronze'
         ELSE 'OK' END,
    CASE WHEN ISNULL(g.Cnt,0) = 0 AND ISNULL(s.Cnt,0) > 0 THEN 'ERROR  Gold empty'
         WHEN ISNULL(g.Cnt,0) < ISNULL(s.Cnt,0)            THEN 'WARN   Gold < Silver'
         ELSE 'OK' END
FROM (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Bronze.Patients GROUP BY Tenant_ID) b
FULL OUTER JOIN (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Silver.Patients GROUP BY Tenant_ID) s
    ON s.Tenant_ID = b.Tenant_ID
FULL OUTER JOIN (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Gold.Dim_Patients WHERE Tenant_ID > 0 GROUP BY Tenant_ID) g
    ON g.Tenant_ID = COALESCE(b.Tenant_ID, s.Tenant_ID)

UNION ALL

SELECT
    COALESCE(b.Tenant_ID, s.Tenant_ID, g.Tenant_ID),
    'Sites',
    ISNULL(b.Cnt, 0), ISNULL(s.Cnt, 0), ISNULL(g.Cnt, 0),
    CASE WHEN ISNULL(s.Cnt,0) = 0 AND ISNULL(b.Cnt,0) > 0 THEN 'ERROR  Silver empty'
         WHEN ISNULL(s.Cnt,0) < ISNULL(b.Cnt,0)            THEN 'WARN   Silver < Bronze'
         ELSE 'OK' END,
    CASE WHEN ISNULL(g.Cnt,0) = 0 AND ISNULL(s.Cnt,0) > 0 THEN 'ERROR  Gold empty'
         WHEN ISNULL(g.Cnt,0) < ISNULL(s.Cnt,0)            THEN 'WARN   Gold < Silver'
         ELSE 'OK' END
FROM (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Bronze.Sites GROUP BY Tenant_ID) b
FULL OUTER JOIN (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Silver.Sites GROUP BY Tenant_ID) s
    ON s.Tenant_ID = b.Tenant_ID
FULL OUTER JOIN (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Gold.Dim_Practice_Sites WHERE Tenant_ID > 0 GROUP BY Tenant_ID) g
    ON g.Tenant_ID = COALESCE(b.Tenant_ID, s.Tenant_ID)

UNION ALL

SELECT
    COALESCE(b.Tenant_ID, s.Tenant_ID, g.Tenant_ID),
    'Treatment_Appointments',
    ISNULL(b.Cnt, 0), ISNULL(s.Cnt, 0), ISNULL(g.Cnt, 0),
    CASE WHEN ISNULL(s.Cnt,0) = 0 AND ISNULL(b.Cnt,0) > 0 THEN 'ERROR  Silver empty'
         WHEN ISNULL(s.Cnt,0) < ISNULL(b.Cnt,0)            THEN 'WARN   Silver < Bronze'
         ELSE 'OK' END,
    CASE WHEN ISNULL(g.Cnt,0) = 0 AND ISNULL(s.Cnt,0) > 0 THEN 'ERROR  Gold empty'
         WHEN ISNULL(g.Cnt,0) < ISNULL(s.Cnt,0)            THEN 'WARN   Gold < Silver'
         ELSE 'OK' END
FROM (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Bronze.Treatment_Appointments GROUP BY Tenant_ID) b
FULL OUTER JOIN (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Silver.Treatment_Appointments GROUP BY Tenant_ID) s
    ON s.Tenant_ID = b.Tenant_ID
FULL OUTER JOIN (SELECT Tenant_ID, COUNT(*) AS Cnt FROM Gold.Fact_Treatment_Appointments WHERE Tenant_ID > 0 GROUP BY Tenant_ID) g
    ON g.Tenant_ID = COALESCE(b.Tenant_ID, s.Tenant_ID)

ORDER BY Entity, Tenant_ID;


-- ============================================================
-- 3. Silver derived / lookup table checks
-- ============================================================
PRINT '';
PRINT '3. Silver derived tables';

SELECT
    'Appointment_Journey_Attrs'  AS Table_Name,
    (SELECT COUNT(*) FROM Silver.Appointment_Journey_Attrs) AS Rows,
    (SELECT COUNT(*) FROM Silver.Appointments)              AS Expected_From,
    'Silver.Appointments'                                   AS Source,
    CASE
        WHEN (SELECT COUNT(*) FROM Silver.Appointment_Journey_Attrs)
           = (SELECT COUNT(*) FROM Silver.Appointments)     THEN 'OK'
        WHEN (SELECT COUNT(*) FROM Silver.Appointment_Journey_Attrs) = 0
                                                            THEN 'ERROR  Empty - Derive SP not run'
        ELSE 'WARN  Count mismatch'
    END AS Status

UNION ALL SELECT
    'Appointment_Reason_Map',
    (SELECT COUNT(*) FROM Silver.Appointment_Reason_Map),
    65, 'Seed data file',
    CASE
        WHEN (SELECT COUNT(*) FROM Silver.Appointment_Reason_Map) = 0
             THEN 'ERROR  Empty - seed script not run'
        WHEN (SELECT COUNT(*) FROM Silver.Appointment_Reason_Map) < 65
             THEN 'WARN  Fewer rows than expected'
        ELSE 'OK'
    END;


-- ============================================================
-- 4. Journey classification breakdown (Appointment_Journey_Attrs)
--    Expect a mix of all four booking types.
--    All-Reception = completed_at / booked_via_api missing upstream.
-- ============================================================
PRINT '';
PRINT '4. Journey classification breakdown';

SELECT
    a.Tenant_ID,
    j.Booking,
    COUNT(*) AS Appointments,
    CAST(ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY a.Tenant_ID), 1) AS DECIMAL(5,1)) AS Pct
FROM Silver.Appointment_Journey_Attrs j
INNER JOIN Silver.Appointments a ON a.Tenant_ID = j.Tenant_ID AND a.Appointment_ID = j.Appointment_ID
GROUP BY a.Tenant_ID, j.Booking
ORDER BY a.Tenant_ID, j.Booking;
