--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Aggregate_Site_Patient_Practitioner_Daily] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Site_Patient_Practitioner_Daily
--  Author           :  AIH
--  Initial Date     :  07/05/2026
--  History          :
--    *01     07/05/2026  AIH  Initial Release
--    *02     07/05/2026  AIH  Fix: precompute BBYL flag (EXISTS illegal inside SUM in Fabric)
--                             Fix: Fact_Treatment_Plan_Items has no fk_Practice_Site column;
--                                  TPI aggregated by patient/practitioner/date only
--    *03     20/05/2026  AIH  Column naming convention fixes (NHS)
--    *04     22/05/2026  AIH  BBYL: use fk_Date_Pending (booking date) not fk_Date_Created
--                             (Silver.Appointments.Created_At is always NULL — not in Dentally API)
--    *05     22/05/2026  AIH  Add Cancelled_Appointments + Short_Notice_Cancellations columns.
--                             Cancellation rows excluded from the appointment spine are aggregated
--                             separately and included via LEFT JOIN (matched dates) or a second
--                             INSERT (cancellation-only dates with no other appointment on that day)
--    *06     13/07/2026  AIH  Chair-utilisation fix (real data): no-patient diary BLOCKS (NOT WORKING/
--                             Lunch/Leave -- ~76% of appt-hours) polluted BOTH sides. Numerator: spine
--                             now requires fk_Patient>0 (blocks/placeholders are not appointments).
--                             Denominator: Worked_Hours = diary avail MINUS on-day block minutes
--                             (interim reason list -> reason-map Block category later).
--    *07     13/07/2026  AIH  Short Notice Cancellations redefined: the reason-map flag
--                             (Dim_Cancellation_Reasons.Is_Short_Notice) is empty on real Dentally
--                             data. Now date-based -- cancelled within @Short_Notice_Days of the
--                             appointment (Cancelled_At vs the appointment date).
--    *08     13/07/2026  AIH  Scheduling pkg: add Chair_Hours (ACTUAL capped in-chair time) +
--                             Tracked_Appointments. Chair time per appt = In_Surgery_Mins (fallback
--                             scheduled Duration if untracked), CAPPED at minutes to the next appt's
--                             start (or diary end-of-day for the last appt) so unclosed-session
--                             outliers can't exceed the slot. Feeds Chair Utilisation (actual) and
--                             Patient Tracked in Surgery %. Appointment_Hours stays scheduled (Diary Fill).
--    *09     13/07/2026  AIH  Dummy diary days: do NOT subtract block minutes from Worked_Hours. The
--                             dummy Available_Clinical_Mins is now the booked patient time (diary *09),
--                             which excludes blocks already; subtracting them again dropped the
--                             denominator below booked -> Diary Fill ~145% / Chair Util ~116% on dummy
--                             days. With worked = booked: Diary Fill 100% by design, Chair Util <=100%.
--    *10     27/07/2026  AIH  Short_Notice_Cancellations now SUMs Fact_Appointments.Is_Short_Notice
--                             (date-based flag moved onto the fact; Dim reason flag dropped). Added
--                             Rebooked_Cancellations (Rebooked_Status = 'Rebooked') -> Cancellation Rebook.
--  Notes:
--    Grain  : Site x Patient x Practitioner x Date x Tenant
--    Pattern: Full DELETE + INSERT each run (no incremental merge).
--    pk      generated via ROW_NUMBER() — no IDENTITY column.
--    NHS_UDAs / NHS_UOAs are NULL pending a claim-level Silver source.
--    BBYL (Book Before You Leave) is approximated as: appointment was
--    completed AND the patient had a new appointment created (booked)
--    on the same calendar day for a future date.
--    Worked_Hours is the practitioner's total clinical availability for
--    the day (from Fact_Practitioner_Diaries); it is the same value
--    across every patient row for that practitioner on that day.
--    TPI measures (Treatment_Count, Open_Treatment_Plan) are joined on
--    patient + practitioner + date only — no site FK exists on that table.
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Load_Aggregate_Site_Patient_Practitioner_Daily
--               @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Aggregate_Site_Patient_Practitioner_Daily]
GO
CREATE PROCEDURE [Gold].[usp_Load_Aggregate_Site_Patient_Practitioner_Daily]
(
      @Mode        VARCHAR(100)     = 'TEST'
    , @Logging     smallint         = 1
    , @Run_UUID    UNIQUEIDENTIFIER = NULL
    , @Run_Inserts BIGINT OUT
    , @Run_Updates BIGINT OUT
    , @Run_Deletes BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        -- ── BBYL flag per appointment ────────────────────────────────────────
        -- Fabric cannot use EXISTS inside an aggregate function, so precompute.
        -- An appointment is BBYL if it was completed AND the patient had a new
        -- appointment created (booked) on the same date for a future date.
        SELECT
            apt.pk_Appointment,
            CASE
                WHEN apt.Is_Completed = 1
                 AND EXISTS (
                        SELECT 1
                        FROM   Gold.Fact_Appointments na
                        WHERE  na.fk_Patient     = apt.fk_Patient
                        AND    na.Tenant_ID      = apt.Tenant_ID
                        AND    na.fk_Date_Pending = apt.fk_Date_Start
                        AND    na.fk_Date_Start  > apt.fk_Date_Start
                 )
                THEN 1 ELSE 0
            END AS Is_BBYL
        INTO #bbyl
        FROM Gold.Fact_Appointments apt
        WHERE apt.Is_Cancelled = 0;

        -- ── Cancellation counts (per site-patient-practitioner-date) ────────────
        -- Built separately because cancelled appointments are excluded from the
        -- appointment spine. Short notice and rebooked are per-appointment flags read
        -- straight off the fact (Fact_Appointments.Is_Short_Notice / Rebooked_Status),
        -- so each definition lives in exactly one place.
        SELECT
            apt.fk_Practice_Site                                                AS fk_Site,
            apt.fk_Patient,
            apt.fk_Practitioner,
            apt.fk_Date_Start                                                   AS fk_Date,
            apt.Tenant_ID,
            COUNT(*)                                                            AS Cancelled_Appointments,
            SUM(CAST(ISNULL(apt.Is_Short_Notice,0) AS INT))                     AS Short_Notice_Cancellations,
            SUM(CASE WHEN apt.Rebooked_Status = 'Rebooked' THEN 1 ELSE 0 END)   AS Rebooked_Cancellations
        INTO #cancel_agg
        FROM Gold.Fact_Appointments apt
        WHERE apt.Is_Cancelled = 1
        GROUP BY
            apt.fk_Practice_Site,
            apt.fk_Patient,
            apt.fk_Practitioner,
            apt.fk_Date_Start,
            apt.Tenant_ID;

        -- ── Appointment spine ────────────────────────────────────────────────
        -- One row per (Site, Patient, Practitioner, Date, Tenant).
        -- Cancelled appointments excluded; DNA are included in Appointments count.
        SELECT
            apt.fk_Practice_Site                                                AS fk_Site,
            apt.fk_Patient,
            apt.fk_Practitioner,
            apt.fk_Date_Start                                                   AS fk_Date,
            apt.Tenant_ID,
            dd.Full_Date                                                        AS Apt_Date,

            COUNT(*)                                                            AS Appointments,
            SUM(CAST(apt.Is_DNA AS INT))                                        AS DNA_Appointments,
            SUM(b.Is_BBYL)                                                      AS BBYL_Appointments,

            -- Exams: Reason contains 'Exam' OR 'HEX' (HEX = combined Exam + Hygiene, so it counts as
            -- an exam). Interim until the appointment reason-map lands; case-insensitive via collation.
            SUM(CASE WHEN apt.Reason LIKE '%Exam%' OR apt.Reason LIKE '%HEX%' OR apt.Reason LIKE '%Hex%'
                     THEN 1 ELSE 0 END)                                        AS Exam_Count,

            -- Appointment_Hours: scheduled clinical time in hours
            CAST(SUM(ISNULL(apt.Duration_Mins, 0)) AS DECIMAL(10,2)) / 60.0   AS Appointment_Hours,

            -- New_Patient: first appointment ever for this patient falls on this date
            MAX(CASE WHEN dp.First_Appointment_Date = dd.Full_Date THEN 1 ELSE 0 END)
                                                                                AS New_Patient,

            -- Future_Appointment: patient currently has a next appointment in the diary
            MAX(CASE WHEN dp.Next_Appointment_Date > dd.Full_Date THEN 1 ELSE 0 END)
                                                                                AS Future_Appointment

        INTO #apt_agg
        FROM  Gold.Fact_Appointments apt
        JOIN  #bbyl                  b   ON b.pk_Appointment = apt.pk_Appointment
        LEFT JOIN Gold.Dim_Patients  dp  ON dp.pk_Patient    = apt.fk_Patient
        LEFT JOIN Gold.Dim_Date      dd  ON dd.pk_Date       = apt.fk_Date_Start
        WHERE apt.Is_Cancelled = 0 AND apt.fk_Patient > 0   -- exclude no-patient diary BLOCKS/placeholders (*06)
        GROUP BY
            apt.fk_Practice_Site,
            apt.fk_Patient,
            apt.fk_Practitioner,
            apt.fk_Date_Start,
            apt.Tenant_ID,
            dd.Full_Date;

        -- ── Revenue (invoice date matched to appointment date) ────────────────
        SELECT
            ii.fk_Practice_Site                                AS fk_Site,
            ii.fk_Patient,
            ii.fk_Practitioner,
            ii.fk_Date_Invoice                                 AS fk_Date,
            ii.Tenant_ID,
            -- Line-grain revenue (NHS_Charge is a 0/1 flag, not an amount): attribute
            -- each line's Total_Price to its practitioner. Invoice header totals are no
            -- longer folded onto lines, so multi-line invoices no longer double-count.
            SUM(CASE WHEN ii.NHS_Charge > 0      THEN ii.Total_Price ELSE 0 END)  AS NHS_Revenue,
            SUM(CASE WHEN ISNULL(ii.NHS_Charge,0) = 0 THEN ii.Total_Price ELSE 0 END) AS Private_Revenue
        INTO #rev_agg
        FROM Gold.Fact_Invoice_Items ii
        GROUP BY
            ii.fk_Practice_Site,
            ii.fk_Patient,
            ii.fk_Practitioner,
            ii.fk_Date_Invoice,
            ii.Tenant_ID;

        -- ── Treatment plan items ─────────────────────────────────────────────
        -- Fact_Treatment_Plan_Items has no fk_Practice_Site; grouped by
        -- patient + practitioner + date + tenant only.
        -- Treatment_Count    : completed items created on this date
        -- Open_Treatment_Plan: open (not completed, not charged) items on this date
        SELECT
            tpi.fk_Patient,
            tpi.fk_Practitioner,
            tpi.fk_Date_Created                                AS fk_Date,
            tpi.Tenant_ID,
            SUM(CAST(tpi.Completed AS INT))                    AS Treatment_Count,
            SUM(CASE WHEN tpi.Completed = 0 AND tpi.Charged = 0 THEN 1 ELSE 0 END)
                                                               AS Open_Treatment_Plan
        INTO #tpi_agg
        FROM Gold.Fact_Treatment_Plan_Items tpi
        GROUP BY
            tpi.fk_Patient,
            tpi.fk_Practitioner,
            tpi.fk_Date_Created,
            tpi.Tenant_ID;

        -- ── Block/unavailable time (must come OUT of worked hours) ────────────
        -- No-patient block appointments (NOT WORKING / Lunch / Annual Leave / Bank Holiday /
        -- Training / Meeting / Medical) are NOT available clinical time. INTERIM explicit reason
        -- list -> replace with the reason-map Block category once the appointment-reason map is
        -- re-seeded from real data.
        DROP TABLE IF EXISTS #block_agg;
        SELECT
            apt.fk_Practitioner,
            apt.fk_Date_Start                                  AS fk_Date,
            apt.Tenant_ID,
            SUM(ISNULL(apt.Duration_Mins,0))                   AS Block_Mins
        INTO #block_agg
        FROM Gold.Fact_Appointments apt
        WHERE apt.Is_Cancelled = 0
          AND (apt.fk_Patient IS NULL OR apt.fk_Patient <= 0)
          AND apt.Reason IN ('NOT WORKING','Not working','Lunch','Annual Leave','Bank Holiday',
                             'Training Course','Meeting','Medical appointment')
        GROUP BY apt.fk_Practitioner, apt.fk_Date_Start, apt.Tenant_ID;

        -- ── Practitioner diary hours (block time subtracted, floored at 0) ────
        -- Available_Clinical_Mins is the scheduled clinical time after breaks; on-day block
        -- appointments are removed so Worked_Hours reflects TRUE available time (*06).
        SELECT
            d.fk_Practitioner,
            d.fk_Date_Day                                      AS fk_Date,
            d.Tenant_ID,
            CAST(CASE
                      -- Dummy days: Available_Clinical_Mins is already the booked patient time; blocks
                      -- are not part of it, so do NOT subtract them (else Diary Fill exceeds 100%).
                      WHEN MAX(CAST(ISNULL(d.Is_Dummy,0) AS INT)) = 1 THEN SUM(d.Available_Clinical_Mins)
                      WHEN SUM(d.Available_Clinical_Mins) - ISNULL(bl.Block_Mins,0) < 0 THEN 0
                      ELSE SUM(d.Available_Clinical_Mins) - ISNULL(bl.Block_Mins,0) END
                 AS DECIMAL(10,2)) / 60.0                      AS Worked_Hours
        INTO #diary_agg
        FROM Gold.Fact_Practitioner_Diaries d
        LEFT JOIN #block_agg bl ON bl.fk_Practitioner = d.fk_Practitioner
                               AND bl.fk_Date        = d.fk_Date_Day
                               AND bl.Tenant_ID      = d.Tenant_ID
        GROUP BY d.fk_Practitioner, d.fk_Date_Day, d.Tenant_ID, bl.Block_Mins;
        DROP TABLE IF EXISTS #block_agg;

        -- ── In-chair (actual, capped) time + tracked count ───────────────────
        -- Chair Utilisation uses the ACTUAL time the patient was in surgery (In_Surgery_Mins),
        -- capped so unclosed-session outliers can't exceed the slot: cap = minutes to the NEXT
        -- appointment's start (same practitioner/day) or, for the last appt, minutes to the diary
        -- end-of-day. Untracked appts (no In_Surgery) fall back to scheduled Duration. Tracked_
        -- Appointments = appts with In_Surgery logged (reception patient-tracking behaviour).
        DROP TABLE IF EXISTS #day_end;
        SELECT d.fk_Practitioner, d.fk_Date_Day AS fk_Date, d.Tenant_ID, MAX(d.End_Time) AS End_Time
        INTO #day_end
        FROM Gold.Fact_Practitioner_Diaries d
        GROUP BY d.fk_Practitioner, d.fk_Date_Day, d.Tenant_ID;

        DROP TABLE IF EXISTS #appt_chair;
        SELECT
            apt.fk_Practice_Site                               AS fk_Site,
            apt.fk_Patient,
            apt.fk_Practitioner,
            apt.fk_Date_Start                                  AS fk_Date,
            apt.Tenant_ID,
            CASE WHEN apt.In_Surgery_Mins > 0 THEN apt.In_Surgery_Mins ELSE ISNULL(apt.Duration_Mins,0) END AS chair_raw,
            CASE WHEN apt.In_Surgery_Mins > 0 THEN 1 ELSE 0 END AS tracked,
            CASE WHEN LEAD(apt.Start_Time) OVER (PARTITION BY apt.Tenant_ID, apt.fk_Practitioner, apt.fk_Date_Start ORDER BY apt.Start_Time, apt.pk_Appointment) IS NOT NULL
                 THEN DATEDIFF(MINUTE, apt.Start_Time, LEAD(apt.Start_Time) OVER (PARTITION BY apt.Tenant_ID, apt.fk_Practitioner, apt.fk_Date_Start ORDER BY apt.Start_Time, apt.pk_Appointment))
                 ELSE COALESCE(NULLIF(DATEDIFF(MINUTE, CAST(apt.Start_Time AS TIME), de.End_Time), 0), apt.Duration_Mins) END AS cap_mins
        INTO #appt_chair
        FROM Gold.Fact_Appointments apt
        LEFT JOIN #day_end de ON de.fk_Practitioner = apt.fk_Practitioner AND de.fk_Date = apt.fk_Date_Start AND de.Tenant_ID = apt.Tenant_ID
        WHERE apt.Is_Cancelled = 0 AND apt.fk_Patient > 0;

        DROP TABLE IF EXISTS #chair_agg;
        SELECT
            ac.fk_Site, ac.fk_Patient, ac.fk_Practitioner, ac.fk_Date, ac.Tenant_ID,
            CAST(SUM(CASE WHEN ac.cap_mins > 0 AND ac.chair_raw > ac.cap_mins THEN ac.cap_mins ELSE ac.chair_raw END) AS DECIMAL(10,2)) / 60.0 AS Chair_Hours,
            SUM(ac.tracked)                                    AS Tracked_Appointments
        INTO #chair_agg
        FROM #appt_chair ac
        GROUP BY ac.fk_Site, ac.fk_Patient, ac.fk_Practitioner, ac.fk_Date, ac.Tenant_ID;
        DROP TABLE IF EXISTS #appt_chair;
        DROP TABLE IF EXISTS #day_end;

        -- ── Full rebuild ─────────────────────────────────────────────────────
        DELETE FROM Gold.Aggregate_Site_Patient_Practitioner_Daily;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Aggregate_Site_Patient_Practitioner_Daily (
            pk_Site_Patient_Practitioner_Daily,
            fk_Site, fk_Patient, fk_Practitioner, fk_Date, Tenant_ID,
            NHS_UDAs, NHS_UOAs,
            Appointments, DNA_Appointments, BBYL_Appointments,
            NHS_Revenue, Private_Revenue,
            Open_Treatment_Plan, Future_Appointment,
            Exam_Count, Treatment_Count, New_Patient,
            Worked_Hours, Appointment_Hours,
            Cancelled_Appointments, Short_Notice_Cancellations, Rebooked_Cancellations,
            Chair_Hours, Tracked_Appointments,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY a.Tenant_ID, a.fk_Date, a.fk_Site, a.fk_Practitioner, a.fk_Patient)
                                                               AS pk_Site_Patient_Practitioner_Daily,
            a.fk_Site,
            a.fk_Patient,
            a.fk_Practitioner,
            a.fk_Date,
            a.Tenant_ID,
            NULL                                               AS NHS_UDAs,  -- pending Silver.NHS_Claims
            NULL                                               AS NHS_UOAs,  -- pending Silver.NHS_Claims
            a.Appointments,
            a.DNA_Appointments,
            a.BBYL_Appointments,
            ISNULL(r.NHS_Revenue,     0)                       AS NHS_Revenue,
            ISNULL(r.Private_Revenue, 0)                       AS Private_Revenue,
            ISNULL(t.Open_Treatment_Plan, 0)                   AS Open_Treatment_Plan,
            CAST(a.Future_Appointment AS BIT)                  AS Future_Appointment,
            a.Exam_Count,
            ISNULL(t.Treatment_Count, 0)                       AS Treatment_Count,
            CAST(a.New_Patient AS BIT)                         AS New_Patient,
            d.Worked_Hours,
            a.Appointment_Hours,
            ISNULL(c.Cancelled_Appointments,     0)            AS Cancelled_Appointments,
            ISNULL(c.Short_Notice_Cancellations, 0)            AS Short_Notice_Cancellations,
            ISNULL(c.Rebooked_Cancellations,     0)            AS Rebooked_Cancellations,
            ISNULL(ch.Chair_Hours, 0)                          AS Chair_Hours,
            ISNULL(ch.Tracked_Appointments, 0)                 AS Tracked_Appointments,
            SYSUTCDATETIME(),
            SYSUTCDATETIME()
        FROM #apt_agg a
        LEFT JOIN #rev_agg    r  ON  r.fk_Site         = a.fk_Site
                                 AND r.fk_Patient       = a.fk_Patient
                                 AND r.fk_Practitioner  = a.fk_Practitioner
                                 AND r.fk_Date          = a.fk_Date
                                 AND r.Tenant_ID        = a.Tenant_ID
        LEFT JOIN #tpi_agg    t  ON  t.fk_Patient      = a.fk_Patient
                                 AND t.fk_Practitioner  = a.fk_Practitioner
                                 AND t.fk_Date          = a.fk_Date
                                 AND t.Tenant_ID        = a.Tenant_ID
        LEFT JOIN #diary_agg  d  ON  d.fk_Practitioner = a.fk_Practitioner
                                 AND d.fk_Date          = a.fk_Date
                                 AND d.Tenant_ID        = a.Tenant_ID
        LEFT JOIN #cancel_agg c  ON  c.fk_Site         = a.fk_Site
                                 AND c.fk_Patient       = a.fk_Patient
                                 AND c.fk_Practitioner  = a.fk_Practitioner
                                 AND c.fk_Date          = a.fk_Date
                                 AND c.Tenant_ID        = a.Tenant_ID
        LEFT JOIN #chair_agg  ch ON  ch.fk_Site         = a.fk_Site
                                 AND ch.fk_Patient      = a.fk_Patient
                                 AND ch.fk_Practitioner = a.fk_Practitioner
                                 AND ch.fk_Date         = a.fk_Date
                                 AND ch.Tenant_ID       = a.Tenant_ID
        WHERE a.fk_Date IS NOT NULL;
        SET @My_Inserts = @@ROWCOUNT;

        -- Insert cancellation-only rows: dates where a practitioner had a
        -- cancellation but no non-cancelled appointment (so not in the spine).
        DECLARE @pk_cancel_base BIGINT = ISNULL(
            (SELECT MAX(pk_Site_Patient_Practitioner_Daily)
             FROM Gold.Aggregate_Site_Patient_Practitioner_Daily), 0);

        INSERT INTO Gold.Aggregate_Site_Patient_Practitioner_Daily (
            pk_Site_Patient_Practitioner_Daily,
            fk_Site, fk_Patient, fk_Practitioner, fk_Date, Tenant_ID,
            NHS_UDAs, NHS_UOAs,
            Appointments, DNA_Appointments, BBYL_Appointments,
            NHS_Revenue, Private_Revenue,
            Open_Treatment_Plan, Future_Appointment,
            Exam_Count, Treatment_Count, New_Patient,
            Worked_Hours, Appointment_Hours,
            Cancelled_Appointments, Short_Notice_Cancellations, Rebooked_Cancellations,
            Chair_Hours, Tracked_Appointments,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_cancel_base + ROW_NUMBER() OVER (ORDER BY c.Tenant_ID, c.fk_Date, c.fk_Site, c.fk_Practitioner, c.fk_Patient)
                                                               AS pk_Site_Patient_Practitioner_Daily,
            c.fk_Site, c.fk_Patient, c.fk_Practitioner, c.fk_Date, c.Tenant_ID,
            NULL, NULL,              -- NHS_UDAs, NHS_UOAs
            0, 0, 0,                 -- Appointments, DNA_Appointments, BBYL_Appointments
            0, 0,                    -- NHS_Revenue, Private_Revenue
            0,                       -- Open_Treatment_Plan
            CAST(0 AS BIT),          -- Future_Appointment
            0, 0,                    -- Exam_Count, Treatment_Count
            CAST(0 AS BIT),          -- New_Patient
            NULL, 0,                 -- Worked_Hours, Appointment_Hours
            c.Cancelled_Appointments,
            c.Short_Notice_Cancellations,
            c.Rebooked_Cancellations,
            NULL, 0,                 -- Chair_Hours, Tracked_Appointments
            SYSUTCDATETIME(),
            SYSUTCDATETIME()
        FROM #cancel_agg c
        WHERE c.fk_Date IS NOT NULL
          AND NOT EXISTS (
            SELECT 1
            FROM #apt_agg a
            WHERE a.fk_Site        = c.fk_Site
              AND a.fk_Patient     = c.fk_Patient
              AND a.fk_Practitioner = c.fk_Practitioner
              AND a.fk_Date        = c.fk_Date
              AND a.Tenant_ID      = c.Tenant_ID
        );
        SET @My_Inserts = @My_Inserts + @@ROWCOUNT;

        DROP TABLE #bbyl;
        DROP TABLE #apt_agg;
        DROP TABLE #rev_agg;
        DROP TABLE #tpi_agg;
        DROP TABLE #diary_agg;
        DROP TABLE #cancel_agg;
        DROP TABLE #chair_agg;

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes
END
GO
