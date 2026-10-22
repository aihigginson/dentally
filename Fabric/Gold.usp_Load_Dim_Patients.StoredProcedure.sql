--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Patients] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Patients
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Add -1 unknown seed row; protect from DELETE
--    *03     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--    *04     19/05/2026  AIH Compute Next_Appointment_Date from Silver.Appointments (future, non-cancelled)
--    *05     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *06     22/05/2026  AIH Add Patient_Count (1 for real rows, 0 for sentinel)
--    *07     29/05/2026  AIH Add fk_Acquisition_Source snowflake FK
--    *08     14/06/2026  AIH Add Is_Email_Missing + Is_Phone_Missing
--    *09     17/06/2026  AIH DATA MINIMISATION (V011): drop special-category + excess-identifier
--                            columns (Title/Middle name, DOB/Age, Gender, Ethnicity, NHS/NI numbers,
--                            Work phone, Address, Medical Alert, Family/Custom, NHS exemption). Retain
--                            identity-for-contact (names + preferred, phone, email), contactability
--                            flags + the non-sensitive operational analytics. Full_Name now First+Last
--                            (no Title). See DPIA.md sec 7.
--    *10     18/06/2026  AIH V014: inactive patients (Active=0) are NOT flagged Is_Email/Phone_Missing
--                            (their contact is deliberately removed in V013, not actionable-missing)
--    *11     19/06/2026  AIH V015: carry contact-preference fields (Use_Email, Use_SMS, Preferred_Phone)
--                            through from Silver (active patients only; NULL for inactive per V013)
--    *12     08/07/2026  AIH V050: Lapsed_Type + fk_Date_Lapsed. Type A "Set as inactive" (Active=0,
--                            lapse date = updated_at); Type B "Calculated as inactive" (Active=1 but
--                            last appointment > 730 days ago, lapse date = last appt + 730). Disjoint
--                            by the Active flag, so a cumulative Lapsed measure = A + B (no overlap).
--    *13     22/07/2026  AIH V110: denormalise Standard_Payment_Plan onto the patient (dedup Silver
--                            plan name + Input.Payment_Plan_Map override) so patients slice by plan
--                            without a per-tenant natural-key relationship. Drives Patients-by-Plan.
--    *14     07/10/2026  AIH V216: Last_Dentist_Visit_Date, Last_Hygienist_Visit_Date and
--                            Last_Allocated_Dentist_Visit_Date -- last seen by role and by
--                            the patient's own allocated dentist, from the appointment book.
--    *15     22/10/2026  AIH V229: fk_Patient_Status (the lifecycle ladder) plus the dentist
--                            relationship -- prior dentist, current spell start, last seen
--                            with the previous dentist, spell count and dentist exam counts.
--                            ==> OWNERSHIP IS ESTABLISHED BY EXAMS, TWO CONSECUTIVE, DATED
--                            FROM THE FIRST. <== The Archived rung keeps pre-migration
--                            records (no attendance, no invoice, no payment) out of every
--                            retention figure -- 19,512 patients at the live tenant.
--    *16     22/10/2026  AIH V233: fk_Current_Dentist and fk_Current_Hygienist. The existing
--                            *_Practitioner_ID columns are Dentally ids and cannot join
--                            Dim_Practitioners, so no patient-grain visual could follow a
--                            Practitioner or Role filter. V229 added the PRIOR key and
--                            missed the current pair.
--    *17     22/10/2026  AIH V235: Dentist_Practitioner_ID and Hygienist_Practitioner_ID
--                            join the UPDATE SET list and the change hash. They were written
--                            by the INSERT and never again, so a reassigned patient kept
--                            their original dentist for ever -- 133 at the live tenant.
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Patients @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Patients]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Patients]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       smallint      = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SET NOCOUNT ON;
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        -- ==> LAST SEEN BY A DENTIST, BY A HYGIENIST, AND BY THEIR OWN DENTIST. <== (V216)
        --
        -- Read from SILVER, not Gold.Fact_Appointments, and that is not a style choice: this
        -- is a dimension, dimensions load before facts, so reading the appointment fact here
        -- would silently answer with yesterday's book. Silver.Appointments is already loaded.
        --
        -- The role comes from Silver.Practitioners.User_Role, which is the exact value
        -- Gold.Dim_Practitioners.Role passes through unchanged -- so a patient's last dentist
        -- visit here and a dentist's appointment list there cannot disagree about who is a
        -- dentist. The collation is case-sensitive, so these literals are the stored case.
        --
        -- Seen is State = 'Completed'. NOT Completed_At IS NOT NULL, which is what the
        -- appointment fact's Is_Completed means: on the live practice 1,004 CANCELLED
        -- appointments carry a Completed_At, and a cancelled appointment is not a visit
        -- however it came to be stamped.
        SELECT a.Tenant_ID, a.Patient_ID, a.Practitioner_ID, pr.User_Role,
               TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time), ''), 10) AS DATE) AS Visit_Date
        INTO   #seen
        FROM   Silver.Appointments a
        JOIN   Silver.Practitioners pr ON pr.Practitioner_ID = a.Practitioner_ID
                                      AND pr.Tenant_ID       = a.Tenant_ID
        WHERE  a.State = 'Completed'
          AND  a.Patient_ID IS NOT NULL
          AND  TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time), ''), 10) AS DATE) <= @Today;

        -- Matched on the patient's CURRENT allocation. A patient reassigned last week
        -- therefore reads as never having seen their new dentist until they next come in,
        -- which is the honest answer: the practice has allocated them to someone who has
        -- not seen them.
        SELECT s.Tenant_ID, s.Patient_ID,
               MAX(CASE WHEN s.User_Role = 'Dentist'   THEN s.Visit_Date END) AS Last_Dentist_Visit_Date,
               MAX(CASE WHEN s.User_Role = 'Hygienist' THEN s.Visit_Date END) AS Last_Hygienist_Visit_Date,
               MAX(CASE WHEN s.Practitioner_ID = pt.Dentist_Practitioner_ID
                        THEN s.Visit_Date END)                                AS Last_Allocated_Dentist_Visit_Date
        INTO   #role_visit
        FROM   #seen s
        JOIN   Silver.Patients pt ON pt.Patient_ID = s.Patient_ID AND pt.Tenant_ID = s.Tenant_ID
        GROUP BY s.Tenant_ID, s.Patient_ID;

        DROP TABLE #seen;

        SELECT
            p.Tenant_ID                                                                             AS Tenant_ID,
            CAST(p.Patient_ID AS INT)                                                               AS Patient_ID,
            CAST(p.Account_ID AS INT)                                                               AS Account_ID,
            NULLIF(TRIM(p.First_Name), '')                                                          AS First_Name,
            NULLIF(TRIM(p.Last_Name), '')                                                           AS Last_Name,
            NULLIF(TRIM(p.Preferred_Name), '')                                                      AS Preferred_Name,
            NULLIF(CONCAT_WS(' ',
                NULLIF(TRIM(p.First_Name), ''),
                NULLIF(TRIM(p.Last_Name), '')), '')                                                 AS Full_Name,
            p.Date_Of_Birth                                                                         AS Date_Of_Birth,
            -- Age AS AT THE LOAD. Derived here rather than left to each report so they cannot
            -- disagree, and stored rather than computed in DAX so it can drive a slicer. The dim
            -- rebuilds nightly, so it is at most a day stale -- which never matters for banding
            -- but would if anyone used it for an exact birthday.
            CASE WHEN p.Date_Of_Birth IS NULL THEN NULL
                 ELSE DATEDIFF(year, p.Date_Of_Birth, CAST(SYSUTCDATETIME() AS DATE))
                      - CASE WHEN DATEADD(year, DATEDIFF(year, p.Date_Of_Birth, CAST(SYSUTCDATETIME() AS DATE)), p.Date_Of_Birth)
                                  > CAST(SYSUTCDATETIME() AS DATE) THEN 1 ELSE 0 END
            END                                                                                     AS Age,
            NULLIF(TRIM(p.Email_Address), '')                                                       AS Email_Address,
            NULLIF(TRIM(p.Home_Phone), '')                                                          AS Home_Phone,
            NULLIF(TRIM(p.Mobile_Phone), '')                                                        AS Mobile_Phone,
            -- Inactive patients have contact deliberately removed (V013), so they are NOT "missing"
            -- contact (the flag drives actionable lists for active patients) -> force 0 when inactive.
            CASE WHEN ISNULL(p.Active,0)=0 THEN 0
                 WHEN NULLIF(TRIM(p.Email_Address),'') IS NULL THEN 1 ELSE 0 END                     AS Is_Email_Missing,
            CASE WHEN ISNULL(p.Active,0)=0 THEN 0
                 WHEN NULLIF(TRIM(p.Mobile_Phone),'') IS NULL
                  AND NULLIF(TRIM(p.Home_Phone),'')   IS NULL THEN 1 ELSE 0 END                      AS Is_Phone_Missing,
            CAST(ISNULL(p.Active, 0) AS BIT)                                                        AS Active,
            CAST(p.Payment_Plan_ID AS INT)                                                          AS Payment_Plan_ID,
            -- Denormalised plan name so patients slice by plan without a (per-tenant, would-fan-out)
            -- model relationship. Same standardisation Dim_Payment_Plans uses (Input.Payment_Plan_Map
            -- override, else the raw plan name). See Patients-by-Plan on My Data.
            COALESCE(NULLIF(TRIM(m.Standard_Payment_Plan), ''),
                     LEFT(NULLIF(TRIM(spp.Payment_Plan_Name), ''), 100))                            AS Standard_Payment_Plan,
            NULLIF(TRIM(p.Site_ID), '')                                                             AS Site_ID,
            NULLIF(TRIM(p.Acquisition_Source_ID), '')                                               AS Acquisition_Source_ID,
            ISNULL(das.pk_Acquisition_Source, -1)                                                   AS fk_Acquisition_Source,
            CAST(p.Dentist_Practitioner_ID AS INT)                                                  AS Dentist_Practitioner_ID,
            CAST(p.Hygienist_Practitioner_ID AS INT)                                                AS Hygienist_Practitioner_ID,
            CAST(p.Dentist_Recall_Date AS DATE)                                                     AS Dentist_Recall_Date,
            CAST(p.Dentist_Recall_Interval AS INT)                                                  AS Dentist_Recall_Interval_Months,
            CAST(p.Hygienist_Recall_Date AS DATE)                                                   AS Hygienist_Recall_Date,
            CAST(p.Hygienist_Recall_Interval AS INT)                                                AS Hygienist_Recall_Interval_Months,
            NULLIF(TRIM(p.Recall_Method), '')                                                       AS Recall_Method,
            p.Use_Email                                                                             AS Use_Email,
            p.Use_SMS                                                                               AS Use_SMS,
            NULLIF(TRIM(p.Preferred_Phone), '')                                                     AS Preferred_Phone,
            -- THE SECOND COLLAPSE, removed in V173. This read NULLIF(p.Marketing_Opt_In, 0),
            -- which threw "opted out" away a second time -- so even once Silver preserved the
            -- three states, Gold would still have shown only "opted in" or nothing. Mapped to
            -- words because the column is varchar and a bare 1/0/NULL on a consent field is read
            -- wrongly by whoever meets it next: NULL here means NEVER ASKED, not "no".
            CASE WHEN p.Marketing_Opt_In = 1 THEN 'Opted in'
                 WHEN p.Marketing_Opt_In = 0 THEN 'Opted out'
                 ELSE 'Never asked'
            END                                                                                     AS Marketing_Consent,
            TRY_CAST(NULLIF(TRIM(ps.First_Appointment_Date), '') AS DATE)                           AS First_Appointment_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date), '') AS DATE)                            AS Last_Appointment_Date,
            next_apt.Next_Appointment_Date                                                          AS Next_Appointment_Date,
            TRY_CAST(NULLIF(TRIM(ps.First_Exam_Date), '') AS DATE)                                  AS First_Exam_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Exam_Date), '') AS DATE)                                   AS Last_Exam_Date,
            TRY_CAST(NULLIF(TRIM(ps.Next_Exam_Date), '') AS DATE)                                   AS Next_Exam_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Scale_And_Polish_Date), '') AS DATE)                       AS Last_Scale_Polish_Date,
            TRY_CAST(NULLIF(TRIM(ps.Next_Scale_And_Polish_Date), '') AS DATE)                       AS Next_Scale_Polish_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_FTA_Appointment_Date), '') AS DATE)                        AS Last_FTA_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Cancelled_Appointment_Date), '') AS DATE)                  AS Last_Cancelled_Appointment_Date,
            rv.Last_Dentist_Visit_Date                                                              AS Last_Dentist_Visit_Date,
            rv.Last_Hygienist_Visit_Date                                                            AS Last_Hygienist_Visit_Date,
            rv.Last_Allocated_Dentist_Visit_Date                                                    AS Last_Allocated_Dentist_Visit_Date,
            CAST(ps.Total_Paid AS DECIMAL(18,4))                                                    AS Total_Paid,
            CAST(ps.Total_Invoiced AS DECIMAL(18,4))                                                AS Total_Invoiced,
            TRY_CAST(p.Created_At AS DATE)                                                          AS Patient_Created_Date,
            TRY_CAST(p.Updated_At AS DATE)                                                          AS Patient_Updated_Date,
            CAST(1 AS INT)                                                                          AS Patient_Count,
            -- Lapsed (V050): Type A "Set as inactive" (Active=0, lapse date = updated_at); Type B
            -- "Calculated as inactive" (Active, last appt > 730d ago AND no future appt booked -- a
            -- booking un-lapses them, recomputed each build; lapse date = last appt + 730). Disjoint
            -- by Active. Date -> Dim_Date (fk_Date_Lapsed) so Lapsed slices by the period it fell in.
            CASE WHEN CAST(ISNULL(p.Active,0) AS BIT) = 0 THEN 'Set as inactive'
                 WHEN TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date),'') AS DATE) <= DATEADD(DAY,-730,@Today)
                      AND next_apt.Next_Appointment_Date IS NULL THEN 'Calculated as inactive'
                 ELSE NULL END                                                                      AS Lapsed_Type,
            dd_lap.pk_Date                                                                          AS fk_Date_Lapsed,
            -- Lapsed_Date = the actual lapse date behind fk_Date_Lapsed; Lapsed_Reason derived from
            -- the lapse type (archived_reason NOT ingested: data-minimised + empty on real data).
            CAST(CASE WHEN CAST(ISNULL(p.Active,0) AS BIT) = 0 THEN TRY_CAST(p.Updated_At AS DATE)
                 WHEN TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date),'') AS DATE) <= DATEADD(DAY,-730,@Today)
                      AND next_apt.Next_Appointment_Date IS NULL
                      THEN DATEADD(DAY,730,TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date),'') AS DATE))
                 ELSE NULL END AS DATE)                                                              AS Lapsed_Date,
            CASE WHEN CAST(ISNULL(p.Active,0) AS BIT) = 0 THEN 'Set inactive in Dentally'
                 WHEN TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date),'') AS DATE) <= DATEADD(DAY,-730,@Today)
                      AND next_apt.Next_Appointment_Date IS NULL THEN 'No visit in 24+ months'
                 ELSE NULL END                                                                      AS Lapsed_Reason
        INTO #src
        FROM Silver.Patients p
        LEFT JOIN Silver.Patient_Stats ps ON ps.Patient_ID = p.Patient_ID AND ps.Tenant_ID = p.Tenant_ID
        LEFT JOIN (
            SELECT   a.Patient_ID,
                     a.Tenant_ID,
                     MIN(TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time),''), 10) AS DATE)) AS Next_Appointment_Date
            FROM     Silver.Appointments a
            WHERE    a.Cancelled_At IS NULL
            AND      TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time),''), 10) AS DATE) > CAST(SYSUTCDATETIME() AS DATE)
            GROUP BY a.Patient_ID, a.Tenant_ID
        ) next_apt ON next_apt.Patient_ID = p.Patient_ID AND next_apt.Tenant_ID = p.Tenant_ID
        LEFT JOIN #role_visit rv ON rv.Patient_ID = p.Patient_ID AND rv.Tenant_ID = p.Tenant_ID
        LEFT JOIN Gold.Dim_Acquisition_Sources das
            ON das.Acquisition_Source_ID = NULLIF(TRIM(p.Acquisition_Source_ID), '')
           AND das.Tenant_ID             = p.Tenant_ID
        -- Plan name for Standard_Payment_Plan. Dedup Silver by (Tenant, Payment_Plan_ID) so a
        -- multi-site plan can't fan out patient rows; then the tenant's standard-name override.
        LEFT JOIN (
            SELECT   Tenant_ID,
                     CAST(Payment_Plan_ID AS INT)          AS Payment_Plan_ID,
                     MAX(NULLIF(TRIM(Payment_Plan_Name), '')) AS Payment_Plan_Name
            FROM     Silver.Payment_Plans
            GROUP BY Tenant_ID, CAST(Payment_Plan_ID AS INT)
        ) spp ON spp.Payment_Plan_ID = CAST(p.Payment_Plan_ID AS INT)
             AND spp.Tenant_ID       = p.Tenant_ID
        LEFT JOIN Input.Payment_Plan_Map m
            ON m.Tenant_ID           = p.Tenant_ID
           AND m.Source_Payment_Plan = spp.Payment_Plan_Name
        LEFT JOIN Gold.Dim_Date dd_lap
            ON dd_lap.Full_Date =
               CASE WHEN CAST(ISNULL(p.Active,0) AS BIT) = 0 THEN TRY_CAST(p.Updated_At AS DATE)
                    WHEN TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date),'') AS DATE) <= DATEADD(DAY,-730,@Today)
                         AND next_apt.Next_Appointment_Date IS NULL
                         THEN DATEADD(DAY, 730, TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date),'') AS DATE))
                    ELSE NULL END
        WHERE p.Patient_ID IS NOT NULL;

        -- ==> THE PATIENT LIFECYCLE, AND WHO THEIR DENTIST ACTUALLY IS. <== (V229)
        --
        -- Read from SILVER for the same reason V216 does: this is a dimension, dimensions
        -- load before facts, so Gold.Fact_Appointments and Gold.Fact_Recalls would answer
        -- with yesterday's book. Silver.Appointments and Silver.Recalls are already loaded.
        --
        -- Seen is State = 'Completed', NOT Completed_At IS NOT NULL -- at the live practice
        -- 1,004 CANCELLED appointments carry a Completed_At, and a cancelled appointment is
        -- not a visit however it came to be stamped.

        -- Any attendance at all. Feeds the ARCHIVE test, which is the only rung that asks
        -- whether this patient has any relationship with the practice on record.
        DROP TABLE IF EXISTS #attend;
        SELECT a.Tenant_ID, a.Patient_ID, COUNT(*) AS Visits
        INTO   #attend
        FROM   Silver.Appointments a
        WHERE  a.State = 'Completed'
          AND  a.Patient_ID IS NOT NULL
          AND  TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time), ''), 10) AS DATE) <= @Today
        GROUP BY a.Tenant_ID, a.Patient_ID;

        -- ==> OWNERSHIP IS ESTABLISHED BY EXAMS, NOT BY VISITS. <== A patient who sees an
        -- unfamiliar dentist for one exam and three follow-up treatment appointments has NOT
        -- changed dentist: the treatments are the consequence of that one exam, not evidence
        -- of a relationship. So only exam-category appointments count here.
        --
        -- The dentist/hygienist split uses Silver.Practitioners.User_Role, exactly as V216
        -- does -- Dentally calls every clinician Dentist or Hygienist, which is precisely
        -- the split needed and is tenant-agnostic. Custom_Role is for comparing clinicians
        -- against their PEERS and is deliberately not used here. The role filter also makes
        -- the reason map's shortcomings harmless on the hygiene side, because a hygienist's
        -- exam cannot establish dentist ownership whatever its reason text says.
        --
        -- ==> REASON TEXT ABSENT FROM Silver.Appointment_Reason_Map IS INVISIBLE HERE. <==
        -- The map is the configuration point and seeding it per customer is an onboarding
        -- task, not something to work around in this loader. 'HEX' was the live practice's
        -- gap -- 15,796 completed appointments across 3,016 patients whose check-ups did not
        -- register as exams at all -- and V229 maps it. Note it is 42% hygienist-performed,
        -- which is harmless here because the User_Role filter drops that half, but it DOES
        -- move the Exam/Hygiene split in Gold.Fact_Appointment_Journey, so that fact is
        -- reloaded in the same release.
        DROP TABLE IF EXISTS #exam;
        SELECT DISTINCT
               a.Tenant_ID,
               a.Patient_ID,
               CAST(a.Practitioner_ID AS INT)                              AS Practitioner_ID,
               TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time), ''), 10) AS DATE)  AS Exam_Date
        INTO   #exam
        FROM   Silver.Appointments a
        JOIN   Silver.Practitioners pr  ON pr.Practitioner_ID = a.Practitioner_ID
                                       AND pr.Tenant_ID       = a.Tenant_ID
        JOIN   Silver.Appointment_Reason_Map arm
                                        ON arm.Reason_Text    = NULLIF(TRIM(a.Reason), '')
        WHERE  a.State          = 'Completed'
          AND  a.Patient_ID IS NOT NULL
          AND  arm.Category     = 'Exam'
          AND  pr.User_Role     = 'Dentist'
          AND  TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time), ''), 10) AS DATE) <= @Today;

        -- Gaps and islands. An island is a RUN of consecutive exams with the same dentist:
        -- subtracting a per-dentist sequence from a per-patient sequence gives every row in
        -- one unbroken run the same constant. Ordering is tie-broken on Practitioner_ID so
        -- two exams on one date cannot make the run assignment arbitrary.
        DROP TABLE IF EXISTS #seq;
        SELECT Tenant_ID, Patient_ID, Practitioner_ID, Exam_Date,
               ROW_NUMBER() OVER (PARTITION BY Tenant_ID, Patient_ID
                                  ORDER BY Exam_Date, Practitioner_ID)
             - ROW_NUMBER() OVER (PARTITION BY Tenant_ID, Patient_ID, Practitioner_ID
                                  ORDER BY Exam_Date, Practitioner_ID) AS Island
        INTO   #seq
        FROM   #exam;

        -- ==> A SPELL NEEDS TWO CONSECUTIVE EXAMS, AND IS DATED FROM THE FIRST. <== One exam
        -- with an unfamiliar dentist is a locum, a holiday cover or an emergency slot. But
        -- the mean gap between a patient's exams at the live practice is 278 days, so
        -- demanding three consecutive exams would take over two years to recognise a change
        -- -- by which time the 24-month lapse test has already fired and the patient is gone.
        -- Two confirms in about nine months, inside the recall cycle. Dating the spell from
        -- the FIRST exam of the run means the history is right even though the change could
        -- only be confirmed at the second.
        DROP TABLE IF EXISTS #spell;
        SELECT Tenant_ID, Patient_ID, Practitioner_ID, Spell_Start, Spell_End, Exams,
               ROW_NUMBER() OVER (PARTITION BY Tenant_ID, Patient_ID
                                  ORDER BY Spell_Start DESC, Practitioner_ID DESC) AS Rev
        INTO   #spell
        FROM (
            SELECT Tenant_ID, Patient_ID, Practitioner_ID,
                   MIN(Exam_Date) AS Spell_Start,
                   MAX(Exam_Date) AS Spell_End,
                   COUNT(*)       AS Exams
            FROM   #seq
            GROUP BY Tenant_ID, Patient_ID, Practitioner_ID, Island
            HAVING COUNT(*) >= 2
        ) z;

        DROP TABLE IF EXISTS #rel;
        SELECT cur.Tenant_ID,
               cur.Patient_ID,
               cur.Practitioner_ID   AS Current_Dentist_Practitioner_ID,
               cur.Spell_Start       AS Current_Dentist_Since_Date,
               prv.Practitioner_ID   AS Prior_Dentist_Practitioner_ID,
               prv.Spell_End         AS Last_Seen_Prior_Dentist_Date,
               sc.Spells             AS Dentist_Spell_Count
        INTO   #rel
        FROM   #spell cur
        LEFT JOIN #spell prv ON prv.Tenant_ID  = cur.Tenant_ID
                            AND prv.Patient_ID = cur.Patient_ID
                            AND prv.Rev        = 2
        CROSS APPLY (SELECT COUNT(*) AS Spells FROM #spell s
                     WHERE s.Tenant_ID = cur.Tenant_ID AND s.Patient_ID = cur.Patient_ID) sc
        WHERE  cur.Rev = 1;

        -- Exams_With_Current_Dentist counts EVERY exam with that dentist, not just the ones
        -- inside the current spell -- a patient who went away and came back knows them from
        -- both. A patient with no qualifying spell has no current dentist, so the column is
        -- 0 rather than NULL: they have exams, just never two running with one person.
        DROP TABLE IF EXISTS #excnt;
        SELECT e.Tenant_ID, e.Patient_ID,
               COUNT(*) AS Dentist_Exam_Count,
               SUM(CASE WHEN e.Practitioner_ID = r.Current_Dentist_Practitioner_ID
                        THEN 1 ELSE 0 END) AS Exams_With_Current_Dentist
        INTO   #excnt
        FROM   #exam e
        LEFT JOIN #rel r ON r.Tenant_ID = e.Tenant_ID AND r.Patient_ID = e.Patient_ID
        GROUP BY e.Tenant_ID, e.Patient_ID;

        -- ==> Silver.Recalls IS ONE ROW PER RECALL. <== Joining it unaggregated multiplies a
        -- patient by their recall count and silently inflates whichever status they land in.
        -- One row per patient, latest due date, tie broken on Id so the pick is deterministic
        -- when two recalls share a date.
        DROP TABLE IF EXISTS #recall;
        SELECT Tenant_ID, Patient_ID, Reminder_Sent, Last_Reminded_Date
        INTO   #recall
        FROM (
            SELECT r.Tenant_ID,
                   CAST(r.Patient_ID AS INT) AS Patient_ID,
                   CASE WHEN NULLIF(TRIM(r.First_Reminder_Sent_At), '') IS NOT NULL
                        THEN 1 ELSE 0 END    AS Reminder_Sent,
                   COALESCE(
                       TRY_CAST(LEFT(NULLIF(TRIM(r.Last_Reminded_At), ''), 10) AS DATE),
                       TRY_CAST(LEFT(NULLIF(TRIM(r.First_Reminder_Sent_At), ''), 10) AS DATE)
                   )                         AS Last_Reminded_Date,
                   ROW_NUMBER() OVER (PARTITION BY r.Tenant_ID, CAST(r.Patient_ID AS INT)
                                      ORDER BY r.Due_Date DESC, r.Id DESC) AS rn
            FROM   Silver.Recalls r
            WHERE  r.Patient_ID IS NOT NULL
        ) z
        WHERE  rn = 1;

        -- ==> THE LADDER. PRECEDENCE IS NOT THE DISPLAY ORDER. <== Archived is tested FIRST,
        -- ahead of both lapsed rungs: a patient with no attendance, no invoice and no payment
        -- anywhere was never lost, because they were never had. At the live practice that is
        -- pre-migration dead weight -- patient records start in 1996, appointments start on
        -- 2012-02-29 -- and calling it lapsed overstates patient loss by an order of
        -- magnitude. See Gold.Dim_Patient_Status for the whole argument.
        --
        -- 'Recall sent' is tested before the recall DATE, because once the practice has
        -- asked, the asking is what the patient is responding to (or not). 60 days is the
        -- two-month line, measured from the LAST time they were chased rather than the
        -- first -- the question is how long they have been silent since being asked.
        DROP TABLE IF EXISTS #ext;
        SELECT s.Tenant_ID,
               s.Patient_ID,
               CAST(CASE
                 WHEN ISNULL(at.Visits, 0) = 0
                      AND ISNULL(s.Total_Invoiced, 0) = 0
                      AND ISNULL(s.Total_Paid, 0)     = 0            THEN 10
                 WHEN s.Lapsed_Type = 'Set as inactive'              THEN  8
                 WHEN s.Lapsed_Type = 'Calculated as inactive'       THEN  7
                 WHEN s.First_Appointment_Date IS NULL
                      AND s.Next_Appointment_Date IS NULL            THEN  9
                 WHEN s.Next_Appointment_Date IS NOT NULL            THEN  1
                 WHEN ISNULL(rc.Reminder_Sent, 0) = 1
                      AND DATEDIFF(DAY, rc.Last_Reminded_Date, @Today) > 60
                                                                     THEN  6
                 WHEN ISNULL(rc.Reminder_Sent, 0) = 1                THEN  5
                 WHEN s.Dentist_Recall_Date IS NULL                  THEN  3
                 WHEN s.Dentist_Recall_Date <= @Today                THEN  4
                 ELSE                                                       2
               END AS INT)                                      AS fk_Patient_Status,
               CAST(dcur.pk_Practitioner AS BIGINT)             AS fk_Current_Dentist,
               CAST(dhyg.pk_Practitioner AS BIGINT)             AS fk_Current_Hygienist,
               CAST(dpr.pk_Practitioner AS BIGINT)              AS fk_Prior_Dentist,
               CAST(dd_cur.pk_Date AS INT)                      AS fk_Date_Current_Dentist_Since,
               r.Current_Dentist_Since_Date                     AS Current_Dentist_Since_Date,
               CAST(dd_prv.pk_Date AS INT)                      AS fk_Date_Last_Seen_Prior_Dentist,
               r.Last_Seen_Prior_Dentist_Date                   AS Last_Seen_Prior_Dentist_Date,
               CAST(ISNULL(r.Dentist_Spell_Count, 0) AS INT)    AS Dentist_Spell_Count,
               -- Settled means they have at least one run of two exams with one dentist. A
               -- patient who has seen a different clinician every single time has not
               -- settled, and that is a different problem from having changed dentist once.
               CAST(CASE WHEN r.Patient_ID IS NULL THEN 0 ELSE 1 END AS BIT)
                                                                AS Has_Settled_Dentist,
               CAST(ISNULL(ec.Dentist_Exam_Count, 0) AS INT)        AS Dentist_Exam_Count,
               CAST(ISNULL(ec.Exams_With_Current_Dentist, 0) AS INT) AS Exams_With_Current_Dentist
        INTO   #ext
        FROM   #src s
        LEFT JOIN #attend at ON at.Tenant_ID = s.Tenant_ID AND at.Patient_ID = s.Patient_ID
        LEFT JOIN #recall rc ON rc.Tenant_ID = s.Tenant_ID AND rc.Patient_ID = s.Patient_ID
        LEFT JOIN #rel    r  ON r.Tenant_ID  = s.Tenant_ID AND r.Patient_ID  = s.Patient_ID
        LEFT JOIN #excnt  ec ON ec.Tenant_ID = s.Tenant_ID AND ec.Patient_ID = s.Patient_ID
        -- Resolved to a surrogate key, not left as a Dentally id: fk_Prior_Dentist is meant
        -- to join Dim_Practitioners in the model. Dim_Practitioners is a dimension and loads
        -- in the same wave, so Audit.Process_Dependency carries an explicit edge for this.
        LEFT JOIN Gold.Dim_Practitioners dpr
               ON dpr.Practitioner_ID = r.Prior_Dentist_Practitioner_ID
              AND dpr.Tenant_ID       = s.Tenant_ID
        -- The CURRENT allocation, resolved from the patient record rather than from a spell:
        -- Dentally's own allocation is the practice's statement of who owns this patient,
        -- and it is what a Practitioner slicer is expected to match.
        LEFT JOIN Gold.Dim_Practitioners dcur
               ON dcur.Practitioner_ID = s.Dentist_Practitioner_ID
              AND dcur.Tenant_ID       = s.Tenant_ID
        LEFT JOIN Gold.Dim_Practitioners dhyg
               ON dhyg.Practitioner_ID = s.Hygienist_Practitioner_ID
              AND dhyg.Tenant_ID       = s.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_cur ON dd_cur.Full_Date = r.Current_Dentist_Since_Date
        LEFT JOIN Gold.Dim_Date dd_prv ON dd_prv.Full_Date = r.Last_Seen_Prior_Dentist_Date;

        DROP TABLE #attend;
        DROP TABLE #exam;
        DROP TABLE #seq;
        DROP TABLE #spell;
        DROP TABLE #rel;
        DROP TABLE #excnt;
        DROP TABLE #recall;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Patients tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Patient_ID = tgt.Patient_ID AND Tenant_ID = tgt.Tenant_ID)
        AND tgt.pk_Patient <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Account_ID                          = src.Account_ID,
            First_Name                          = src.First_Name,
            Last_Name                           = src.Last_Name,
            Preferred_Name                      = src.Preferred_Name,
            Full_Name                           = src.Full_Name,
            Date_Of_Birth                       = src.Date_Of_Birth,
            Age                                 = src.Age,
            Email_Address                       = src.Email_Address,
            Home_Phone                          = src.Home_Phone,
            Mobile_Phone                        = src.Mobile_Phone,
            Is_Email_Missing                    = src.Is_Email_Missing,
            Is_Phone_Missing                    = src.Is_Phone_Missing,
            Active                              = src.Active,
            Payment_Plan_ID                     = src.Payment_Plan_ID,
            Standard_Payment_Plan               = src.Standard_Payment_Plan,
            Site_ID                             = src.Site_ID,
            fk_Acquisition_Source               = src.fk_Acquisition_Source,
            Dentist_Recall_Date                 = src.Dentist_Recall_Date,
            Dentist_Recall_Interval_Months      = src.Dentist_Recall_Interval_Months,
            Hygienist_Recall_Date               = src.Hygienist_Recall_Date,
            Hygienist_Recall_Interval_Months    = src.Hygienist_Recall_Interval_Months,
            Recall_Method                       = src.Recall_Method,
            Use_Email                           = src.Use_Email,
            Use_SMS                             = src.Use_SMS,
            Preferred_Phone                     = src.Preferred_Phone,
            Marketing_Consent                   = src.Marketing_Consent,
            First_Appointment_Date              = src.First_Appointment_Date,
            Last_Appointment_Date               = src.Last_Appointment_Date,
            Next_Appointment_Date               = src.Next_Appointment_Date,
            First_Exam_Date                     = src.First_Exam_Date,
            Last_Exam_Date                      = src.Last_Exam_Date,
            Next_Exam_Date                      = src.Next_Exam_Date,
            Last_Scale_Polish_Date              = src.Last_Scale_Polish_Date,
            Next_Scale_Polish_Date              = src.Next_Scale_Polish_Date,
            Last_FTA_Date                       = src.Last_FTA_Date,
            Last_Cancelled_Appointment_Date     = src.Last_Cancelled_Appointment_Date,
            Last_Dentist_Visit_Date             = src.Last_Dentist_Visit_Date,
            Last_Hygienist_Visit_Date           = src.Last_Hygienist_Visit_Date,
            Last_Allocated_Dentist_Visit_Date   = src.Last_Allocated_Dentist_Visit_Date,
            Total_Paid                          = src.Total_Paid,
            Total_Invoiced                      = src.Total_Invoiced,
            Patient_Updated_Date                = src.Patient_Updated_Date,
            Lapsed_Type                         = src.Lapsed_Type,
            fk_Date_Lapsed                      = src.fk_Date_Lapsed,
            Lapsed_Date                         = src.Lapsed_Date,
            Lapsed_Reason                       = src.Lapsed_Reason,
            fk_Patient_Status                   = ext.fk_Patient_Status,
            -- V235: these were in #src and the INSERT but in neither the SET list nor the
            -- hash, so a reassigned list was never picked up for an existing patient.
            Dentist_Practitioner_ID             = src.Dentist_Practitioner_ID,
            Hygienist_Practitioner_ID           = src.Hygienist_Practitioner_ID,
            fk_Current_Dentist                  = ext.fk_Current_Dentist,
            fk_Current_Hygienist                = ext.fk_Current_Hygienist,
            fk_Prior_Dentist                    = ext.fk_Prior_Dentist,
            fk_Date_Current_Dentist_Since       = ext.fk_Date_Current_Dentist_Since,
            Current_Dentist_Since_Date          = ext.Current_Dentist_Since_Date,
            fk_Date_Last_Seen_Prior_Dentist     = ext.fk_Date_Last_Seen_Prior_Dentist,
            Last_Seen_Prior_Dentist_Date        = ext.Last_Seen_Prior_Dentist_Date,
            Dentist_Spell_Count                 = ext.Dentist_Spell_Count,
            Has_Settled_Dentist                 = ext.Has_Settled_Dentist,
            Dentist_Exam_Count                  = ext.Dentist_Exam_Count,
            Exams_With_Current_Dentist          = ext.Exams_With_Current_Dentist,
            DW_Updated_At                       = SYSUTCDATETIME()
        FROM Gold.Dim_Patients tgt
        INNER JOIN #src src ON tgt.Patient_ID = src.Patient_ID AND tgt.Tenant_ID = src.Tenant_ID
        INNER JOIN #ext ext ON ext.Patient_ID = src.Patient_ID AND ext.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Account_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Preferred_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Date_Of_Birth] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Age] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Email_Address] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Home_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Email_Missing] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Phone_Missing] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Payment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Standard_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Acquisition_Source] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Hygienist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Hygienist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Recall_Method] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Use_Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Use_SMS] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Preferred_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Marketing_Consent] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Next_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Next_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Next_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_FTA_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Cancelled_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Dentist_Visit_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Hygienist_Visit_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Allocated_Dentist_Visit_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Total_Paid] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Total_Invoiced] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Updated_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Lapsed_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Patient_Status] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Prior_Dentist] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Current_Dentist] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Practitioner_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Hygienist_Practitioner_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Current_Hygienist] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Current_Dentist_Since_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Seen_Prior_Dentist_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Spell_Count] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Has_Settled_Dentist] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Exam_Count] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Exams_With_Current_Dentist] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Lapsed] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Lapsed_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Lapsed_Reason] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Account_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Preferred_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Date_Of_Birth] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Age] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Email_Address] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Home_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Email_Missing] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Phone_Missing] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Payment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Standard_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Acquisition_Source] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Dentist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Dentist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Hygienist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Hygienist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Recall_Method] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Use_Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Use_SMS] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Preferred_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Marketing_Consent] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Next_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Next_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Next_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_FTA_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Cancelled_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Dentist_Visit_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Hygienist_Visit_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Allocated_Dentist_Visit_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Total_Paid] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Total_Invoiced] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Updated_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Lapsed_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(ext.[fk_Patient_Status] AS VARCHAR(500)), ''),
           ISNULL(CAST(ext.[fk_Prior_Dentist] AS VARCHAR(500)), ''),
           ISNULL(CAST(ext.[fk_Current_Dentist] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Dentist_Practitioner_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Hygienist_Practitioner_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(ext.[fk_Current_Hygienist] AS VARCHAR(500)), ''),
           ISNULL(CAST(ext.[Current_Dentist_Since_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(ext.[Last_Seen_Prior_Dentist_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(ext.[Dentist_Spell_Count] AS VARCHAR(500)), ''),
           ISNULL(CAST(ext.[Has_Settled_Dentist] AS VARCHAR(500)), ''),
           ISNULL(CAST(ext.[Dentist_Exam_Count] AS VARCHAR(500)), ''),
           ISNULL(CAST(ext.[Exams_With_Current_Dentist] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Lapsed] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Lapsed_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Lapsed_Reason] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_Patient_base BIGINT = ISNULL((SELECT MAX(pk_Patient) FROM Gold.Dim_Patients WHERE pk_Patient > 0), 0);
        INSERT INTO Gold.Dim_Patients (
            pk_Patient,
            Tenant_ID, Patient_ID, Account_ID, First_Name, Last_Name, Preferred_Name, Full_Name,
            Date_Of_Birth, Age, Email_Address, Home_Phone, Mobile_Phone, Is_Email_Missing, Is_Phone_Missing,
            Active, Payment_Plan_ID, Standard_Payment_Plan, Site_ID,
            Acquisition_Source_ID, fk_Acquisition_Source, Dentist_Practitioner_ID, Hygienist_Practitioner_ID,
            Dentist_Recall_Date, Dentist_Recall_Interval_Months,
            Hygienist_Recall_Date, Hygienist_Recall_Interval_Months,
            Recall_Method, Use_Email, Use_SMS, Preferred_Phone, Marketing_Consent,
            First_Appointment_Date, Last_Appointment_Date, Next_Appointment_Date,
            First_Exam_Date, Last_Exam_Date, Next_Exam_Date,
            Last_Scale_Polish_Date, Next_Scale_Polish_Date,
            Last_FTA_Date, Last_Cancelled_Appointment_Date,
            Last_Dentist_Visit_Date, Last_Hygienist_Visit_Date, Last_Allocated_Dentist_Visit_Date,
            Total_Paid, Total_Invoiced,
            Patient_Created_Date, Patient_Updated_Date, Lapsed_Type, fk_Date_Lapsed, Lapsed_Date, Lapsed_Reason, Patient_Count,
            fk_Patient_Status, fk_Prior_Dentist, fk_Current_Dentist, fk_Current_Hygienist,
            fk_Date_Current_Dentist_Since, Current_Dentist_Since_Date,
            fk_Date_Last_Seen_Prior_Dentist, Last_Seen_Prior_Dentist_Date,
            Dentist_Spell_Count, Has_Settled_Dentist,
            Dentist_Exam_Count, Exams_With_Current_Dentist,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_Patient_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Patient_ID),
            src.Tenant_ID, src.Patient_ID, src.Account_ID, src.First_Name, src.Last_Name,
            src.Preferred_Name, src.Full_Name, src.Date_Of_Birth, src.Age, src.Email_Address,
            src.Home_Phone, src.Mobile_Phone, src.Is_Email_Missing, src.Is_Phone_Missing,
            src.Active, src.Payment_Plan_ID, src.Standard_Payment_Plan, src.Site_ID,
            src.Acquisition_Source_ID, src.fk_Acquisition_Source, src.Dentist_Practitioner_ID, src.Hygienist_Practitioner_ID,
            src.Dentist_Recall_Date, src.Dentist_Recall_Interval_Months,
            src.Hygienist_Recall_Date, src.Hygienist_Recall_Interval_Months,
            src.Recall_Method, src.Use_Email, src.Use_SMS, src.Preferred_Phone, src.Marketing_Consent,
            src.First_Appointment_Date, src.Last_Appointment_Date, src.Next_Appointment_Date,
            src.First_Exam_Date, src.Last_Exam_Date, src.Next_Exam_Date,
            src.Last_Scale_Polish_Date, src.Next_Scale_Polish_Date,
            src.Last_FTA_Date, src.Last_Cancelled_Appointment_Date,
            src.Last_Dentist_Visit_Date, src.Last_Hygienist_Visit_Date, src.Last_Allocated_Dentist_Visit_Date,
            src.Total_Paid, src.Total_Invoiced,
            src.Patient_Created_Date, src.Patient_Updated_Date, src.Lapsed_Type, src.fk_Date_Lapsed, src.Lapsed_Date, src.Lapsed_Reason, src.Patient_Count,
            ext.fk_Patient_Status, ext.fk_Prior_Dentist, ext.fk_Current_Dentist, ext.fk_Current_Hygienist,
            ext.fk_Date_Current_Dentist_Since, ext.Current_Dentist_Since_Date,
            ext.fk_Date_Last_Seen_Prior_Dentist, ext.Last_Seen_Prior_Dentist_Date,
            ext.Dentist_Spell_Count, ext.Has_Settled_Dentist,
            ext.Dentist_Exam_Count, ext.Exams_With_Current_Dentist,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        INNER JOIN #ext ext ON ext.Patient_ID = src.Patient_ID AND ext.Tenant_ID = src.Tenant_ID
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Patients tgt WHERE tgt.Patient_ID = src.Patient_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
        DROP TABLE #role_visit;
        DROP TABLE #ext;

        -- Ensure unknown/-1 seed row exists (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_Patients (pk_Patient, Tenant_ID, Patient_ID, Patient_Count, fk_Patient_Status, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, -1, 0, -1, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Patients WHERE pk_Patient = -1);
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
