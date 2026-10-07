--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Data_Quality_Detail] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Data_Quality_Detail
--  Author           :  AIH
--  Initial Date     :  23/09/2026
--  History          :
--    *01     23/09/2026  AIH  Initial Release (V176)
--    *02     07/10/2026  AIH  V216: PLAN_DENTIST_NOT_SEEN + the Dentist/Hygienist visit pair
--  Notes:
--    Grain  : one row per offending record per check -- the named list behind every count on
--             Gold.Aggregate_Data_Quality.
--    Pattern: Full DELETE + INSERT each run. pk via ROW_NUMBER() -- no IDENTITY.
--
--    ==> THE PREDICATES HERE MUST MATCH usp_Load_Aggregate_Data_Quality EXACTLY. <== The two
--    procedures answer the same question at different grains, and nothing enforces that they
--    agree. If they drift, the scorecard says 471 and the drillthrough lists 460, which is
--    worse than having no drillthrough at all -- the practice stops trusting both numbers.
--    Every branch below is a copy of its opposite number with the COUNT(*) replaced by the
--    identifying columns. Change one, change the other, and the guard in V176's manifest
--    re-checks the totals after every load.
--
--    Diary checks test Is_Patient_Appointment for the reason given in the aggregate: lunch,
--    admin time and held slots live in Fact_Appointments but carry no patient.
--
--    PAT_NO_MARKETING_PREF is the one check whose detail is not worth reading -- 6,739 names
--    is not a worklist -- but it is included anyway so that no check on the scorecard is a
--    dead end when someone clicks it.
--
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Load_Fact_Data_Quality_Detail
--               @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Data_Quality_Detail]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Data_Quality_Detail]
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

-- ==> "NOTHING BOOKED" MEANS NO APPOINTMENT FROM TODAY ONWARDS, NOT FROM TOMORROW. <==
        -- These four checks all exclude a patient who has an appointment coming. They used
        -- Next_Appointment_Date <= @Today, which admits an appointment TODAY -- so a patient
        -- sitting in the waiting room counted as having nothing booked. On tenant 100 that put
        -- 9 rows on the worklist that contradicted themselves on screen: the Next in column
        -- said "1: Today" beside a finding whose whole premise is that nothing is booked.
        -- Tony Rushbrook, last seen January 2020, in the chair today, listed as Dormant.
        --
        -- The band below uses >= @Today, so < @Today here makes the two exact complements:
        -- a row shows a Next in date if and only if the check has excluded it. No gap, and
        -- the contradiction cannot come back by one of the pair being edited alone.
        DECLARE @Today          DATE = CAST(SYSUTCDATETIME() AS DATE);
        DECLARE @Recent_Days    INT  = 90;
        DECLARE @Dormant_Months INT  = 24;
        -- ==> TWELVE MONTHS, NOT SIX. <== Six was the first cut and it was too tight: it
        -- flagged 201 of 1,405 plan patients on the live practice, and most of that is the
        -- ordinary drift between a recall falling due and the appointment happening -- the
        -- owner's words, "it is fairly common for patients to be over 6 months in the normal
        -- course of events". A plan buys two exams a year, so at twelve months the patient
        -- has missed a whole year of what they are paying for and nobody can call it drift.
        -- Twelve flags 102. A check that cries wolf 201 times is a check nobody opens.
        DECLARE @Plan_Months    INT  = 12;

        -- ==> WHO IS A PLAN PATIENT? THE OWNER'S RATE TABLE SAYS SO. <== (V216)
        --
        -- Input.Plan_Capitation_Rate is the curated list of payment plans that ARE plans, and
        -- it is what Gold.Fact_Revenue_Capitation bills against -- so this check and the
        -- capitation it protects count the same members. On the live practice that is 1,410
        -- active patients, exactly the eight Denplan tiers, with no per-tenant plan name
        -- hard-coded anywhere.
        --
        -- NOT Gold.Fact_Plan_Spell: a spell is reconstructed from attended free exams, so a
        -- member who has never been through the door has no spell -- and they are the single
        -- most important row on this list. Using the spell would have hidden 36 of them.
        --
        -- LEFT JOIN to the practitioner dim, not an inner one. A plan member with no allocated
        -- dentist is still paying and can still have stopped attending, so PLAN_INACTIVE must
        -- see them; PLAN_MISALLOCATED cannot -- there is nothing to compare against -- and
        -- excludes them in its own branch rather than here.
        SELECT p.Tenant_ID, p.pk_Patient, p.Patient_ID, p.Full_Name, p.Standard_Payment_Plan,
               p.Last_Appointment_Date, p.Last_Dentist_Visit_Date, p.Last_Hygienist_Visit_Date,
               p.Last_Allocated_Dentist_Visit_Date,
               CAST(alloc.Full_Name AS VARCHAR(255)) AS Allocated_Dentist
        INTO   #plan_patient
        FROM   Gold.Dim_Patients p
        LEFT JOIN Gold.Dim_Practitioners alloc ON alloc.Tenant_ID       = p.Tenant_ID
                                             AND alloc.Practitioner_ID = p.Dentist_Practitioner_ID
        WHERE  p.pk_Patient > 0 AND p.Active = 1
          AND  EXISTS (SELECT 1 FROM Input.Plan_Capitation_Rate r
                       WHERE r.Tenant_ID = p.Tenant_ID AND r.Payment_Plan_ID = p.Payment_Plan_ID);

        -- The supporting pair: visits over the SAME window the check tests -- which is what
        -- makes nought and nought mean "has not been in at all" rather than "not lately".
        -- Counted across all clinicians of that role, one row per patient, so it cannot fan
        -- the detail out.
        SELECT a.Tenant_ID, a.fk_Patient,
               SUM(CASE WHEN pr.Role = 'Dentist'   THEN 1 ELSE 0 END) AS Dentist_Visits,
               SUM(CASE WHEN pr.Role = 'Hygienist' THEN 1 ELSE 0 END) AS Hygienist_Visits
        INTO   #plan_visit
        FROM   Gold.Fact_Appointments a
        JOIN   Gold.Dim_Date d           ON d.pk_Date          = a.fk_Date_Start
        JOIN   Gold.Dim_Practitioners pr ON pr.pk_Practitioner = a.fk_Practitioner
        WHERE  a.State = 'Completed'
          AND  d.Full_Date <= @Today
          AND  d.Full_Date >= DATEADD(MONTH, -@Plan_Months, @Today)
        GROUP BY a.Tenant_ID, a.fk_Patient;

        -- ==> AND WHO IS ACTUALLY SEEING THEM. <== Without this the row says the allocation is
        -- wrong and leaves the reader to go and find out who it should be, one patient at a
        -- time. The most recent dentist in the window is the answer in all but the awkward
        -- cases, and the awkward cases are why the visit counts are on the row too.
        SELECT x.Tenant_ID, x.fk_Patient, x.Seen_By
        INTO   #plan_seen_by
        FROM (
            SELECT a.Tenant_ID, a.fk_Patient,
                   CAST(pr.Full_Name AS VARCHAR(255)) AS Seen_By,
                   ROW_NUMBER() OVER (PARTITION BY a.Tenant_ID, a.fk_Patient
                                      ORDER BY d.Full_Date DESC, pr.pk_Practitioner) AS rn
            FROM   Gold.Fact_Appointments a
            JOIN   Gold.Dim_Date d           ON d.pk_Date          = a.fk_Date_Start
            JOIN   Gold.Dim_Practitioners pr ON pr.pk_Practitioner = a.fk_Practitioner
            WHERE  a.State = 'Completed'
              AND  pr.Role = 'Dentist'
              AND  d.Full_Date <= @Today
              AND  d.Full_Date >= DATEADD(MONTH, -@Plan_Months, @Today)
        ) x
        WHERE  x.rn = 1;

        -- Appointments with a real calendar date, flagged as in the aggregate.
        SELECT a.Tenant_ID, a.fk_Patient, a.fk_Practitioner, a.State,
               ISNULL(a.Is_Cancelled, 0) AS Is_Cancelled,
               d.Full_Date               AS Appt_Date,
               CAST(CASE WHEN a.fk_Patient > 0 THEN 1 ELSE 0 END AS BIT) AS Is_Patient_Appointment
        INTO #appt
        FROM Gold.Fact_Appointments a
        JOIN Gold.Dim_Date d ON d.pk_Date = a.fk_Date_Start;

        -- ── One row per offending record ─────────────────────────────────────
        -- ==> EVERY STRING COLUMN IS CAST HERE. <== Fabric Warehouse has no nvarchar at all,
        -- and SELECT ... INTO takes whatever type the expression produced -- concatenation and
        -- FORMAT() both yield nvarchar(4000), which the insert then rejects with "The data type
        -- 'nvarchar(4000)' ... is not supported in this edition of SQL Server", naming the
        -- column but not the cause. The casts sit in this SELECT list because that is what
        -- determines the temp table's columns.
        --
        -- And it has to be SELECT ... INTO, not CREATE TABLE #hits + INSERT: Fabric rejects the
        -- latter from a query over warehouse tables with "references an object that is not
        -- supported in distributed processing mode". Both failures were hit deploying this.
        SELECT Check_Code, Tenant_ID, fk_Patient,
               CAST(Record_Type      AS VARCHAR(20))  AS Record_Type,
               CAST(Record_Name      AS VARCHAR(200)) AS Record_Name,
               CAST(Record_Reference AS VARCHAR(100)) AS Record_Reference,
               Detail_Date,
               CAST(Detail_Label     AS VARCHAR(50))  AS Detail_Label,
               CAST(Detail_Note      AS VARCHAR(300)) AS Detail_Note
        INTO #hits
        FROM (
            -- Diary ───────────────────────────────────────────────────────────
            SELECT 'DIARY_LEAVER_BOOKED' AS Check_Code, a.Tenant_ID,
                   p.pk_Patient AS fk_Patient, 'Appointment' AS Record_Type,
                   p.Full_Name AS Record_Name,
                   CAST(p.Patient_ID AS VARCHAR(100)) AS Record_Reference,
                   a.Appt_Date AS Detail_Date, 'Appointment' AS Detail_Label,
                   'Booked with ' + pr.Full_Name + ', who has left' AS Detail_Note
            FROM #appt a
            JOIN Gold.Dim_Practitioners pr ON pr.pk_Practitioner = a.fk_Practitioner
                                          AND pr.Tenant_ID       = a.Tenant_ID
            JOIN Gold.Dim_Patients p ON p.pk_Patient = a.fk_Patient AND p.Tenant_ID = a.Tenant_ID
            WHERE a.Appt_Date > @Today AND a.Is_Cancelled = 0
              AND a.Is_Patient_Appointment = 1 AND pr.Active = 0

            UNION ALL
            SELECT 'DIARY_INACTIVE_PATIENT', a.Tenant_ID, p.pk_Patient, 'Appointment',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   a.Appt_Date, 'Appointment',
                   -- V013 replaces an inactive patient's name with the placeholder "Inactive
                   -- Patient", so Record_Name cannot identify them here. Record_Reference (the
                   -- Dentally patient id) is how this row gets actioned, and the note says so
                   -- rather than leaving the reader staring at a list of identical names.
                   'Patient is marked inactive; appointment state ' + ISNULL(a.State, 'unknown')
                   + ' -- look the patient up in Dentally by ID, the name is withheld while inactive'
            FROM #appt a
            JOIN Gold.Dim_Patients p ON p.pk_Patient = a.fk_Patient AND p.Tenant_ID = a.Tenant_ID
            WHERE a.Appt_Date > @Today AND a.Is_Cancelled = 0
              AND a.Is_Patient_Appointment = 1
              AND p.pk_Patient > 0 AND p.Active = 0

            UNION ALL
            SELECT 'DIARY_NOT_CLOSED', a.Tenant_ID, p.pk_Patient, 'Appointment',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   a.Appt_Date, 'Appointment',
                   'Still showing as ' + a.State + ' with ' + ISNULL(pr.Full_Name, 'no clinician')
            FROM #appt a
            JOIN Gold.Dim_Patients p ON p.pk_Patient = a.fk_Patient AND p.Tenant_ID = a.Tenant_ID
            LEFT JOIN Gold.Dim_Practitioners pr ON pr.pk_Practitioner = a.fk_Practitioner
                                               AND pr.Tenant_ID       = a.Tenant_ID
            WHERE a.Appt_Date <  @Today
              AND a.Appt_Date >= DATEADD(DAY, -@Recent_Days, @Today)
              AND a.Is_Patient_Appointment = 1
              AND a.State IN ('Pending', 'Confirmed')

            UNION ALL
            SELECT 'DIARY_LEFT_OPEN', a.Tenant_ID, p.pk_Patient, 'Appointment',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   a.Appt_Date, 'Appointment',
                   'Checked in and never checked out -- left at ' + a.State
            FROM #appt a
            JOIN Gold.Dim_Patients p ON p.pk_Patient = a.fk_Patient AND p.Tenant_ID = a.Tenant_ID
            WHERE a.Appt_Date <  @Today
              AND a.Appt_Date >= DATEADD(DAY, -@Recent_Days, @Today)
              AND a.Is_Patient_Appointment = 1
              AND a.State IN ('Arrived', 'In surgery')

            -- Patients ────────────────────────────────────────────────────────
            UNION ALL
            SELECT 'PAT_NO_CONTACT', p.Tenant_ID, p.pk_Patient, 'Patient',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   p.Last_Appointment_Date, 'Last seen',
                   'No phone and no email on the record'
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Is_Email_Missing = 1 AND p.Is_Phone_Missing = 1

            UNION ALL
            SELECT 'PAT_NO_RECALL_DATE', p.Tenant_ID, p.pk_Patient, 'Patient',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   p.Last_Appointment_Date, 'Last seen',
                   'No dentist or hygienist recall date set'
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Dentist_Recall_Date IS NULL AND p.Hygienist_Recall_Date IS NULL
              -- See the note on this check in usp_Load_Aggregate_Data_Quality: a future
              -- appointment answers the finding, so it is not on the worklist.
              AND (p.Next_Appointment_Date IS NULL OR p.Next_Appointment_Date < @Today)

            UNION ALL
            SELECT 'PAT_DORMANT', p.Tenant_ID, p.pk_Patient, 'Patient',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   p.Last_Appointment_Date, 'Last seen',
                   'Value 3yr £' + CAST(CAST(ISNULL(pv.Value_Total, 0) AS INT) AS VARCHAR(20))
                   + ISNULL(' -- ' + NULLIF(p.Email_Address, ''), '')
            -- ==> THE WORKLIST IS ORDERED BY THIS NUMBER, SO IT HAD BETTER BE THE RIGHT
            -- ONE. <== It read Dim_Patients.Total_Paid, which is the INVOICED total from
            -- patient_stats and carries none of a membership patient's monthly fee. On the
            -- live practice a plan patient is worth 2,876 against a private patient's
            -- 1,414, but showed as 737 -- so the most valuable dormant patients in the
            -- practice sat at the bottom of the list somebody works down.
            --
            -- Nor was it a lifetime: Dentally holds nothing from before a practice migrates
            -- onto it, so "lifetime" silently meant a different span for every customer.
            -- The value columns on Aggregate_Site_Patient_Current are a rolling 36 months of
            -- BOTH revenue types. They lived on their own aggregate for one release; it was
            -- the same grain as this one, so it was folded in rather than kept in parallel.
            FROM Gold.Dim_Patients p
            LEFT JOIN Gold.Aggregate_Site_Patient_Current pv
                   ON pv.fk_Patient = p.pk_Patient AND pv.Tenant_ID = p.Tenant_ID
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Last_Appointment_Date < DATEADD(MONTH, -@Dormant_Months, @Today)
              AND (p.Next_Appointment_Date IS NULL OR p.Next_Appointment_Date < @Today)

            -- ==> BOTH PREDICATES MUST MATCH usp_Load_Aggregate_Data_Quality EXACTLY. <== (V216)
            --
            -- Neither is narrowed by whether anything is booked, unlike PAT_DORMANT. For the
            -- first the fee has already gone uncollected-against for a year; for the second an
            -- appointment next week with somebody else does not answer the finding. The Next in
            -- column on the row says whether they are coming, which is all that exclusion was
            -- ever for.
            --
            -- DISJOINT BY CONSTRUCTION: the first requires no visits in the window, the second
            -- requires at least one. A patient cannot appear on both, and the two together are
            -- every plan member who is not getting the care they pay for.
            UNION ALL
            SELECT 'PLAN_INACTIVE', pp.Tenant_ID, pp.pk_Patient, 'Patient',
                   pp.Full_Name, CAST(pp.Patient_ID AS VARCHAR(100)),
                   pp.Last_Appointment_Date, 'Last visit',
                   -- Front-loaded: the column truncates the tail, so the name of whoever owns
                   -- this patient has to be inside the first few words. The plan tier is the
                   -- part that can fall off the end without costing the reader anything.
                   CASE WHEN pp.Last_Appointment_Date IS NULL THEN 'Never attended. ' ELSE '' END
                   + ISNULL(pp.Allocated_Dentist + '''s list', 'No allocated dentist')
                   + ISNULL('. ' + pp.Standard_Payment_Plan, '')
            FROM #plan_patient pp
            LEFT JOIN #plan_visit pv ON pv.Tenant_ID = pp.Tenant_ID AND pv.fk_Patient = pp.pk_Patient
            WHERE ISNULL(pv.Dentist_Visits, 0) = 0 AND ISNULL(pv.Hygienist_Visits, 0) = 0

            UNION ALL
            SELECT 'PLAN_MISALLOCATED', pp.Tenant_ID, pp.pk_Patient, 'Patient',
                   pp.Full_Name, CAST(pp.Patient_ID AS VARCHAR(100)),
                   pp.Last_Allocated_Dentist_Visit_Date, 'Own dentist last seen',
                   -- Both names inside the first fifty characters, because that is the whole
                   -- finding: this person, not that person. Everything after them is context.
                   ISNULL('Seeing ' + sb.Seen_By + ', not ', 'Not seen by ')
                   + pp.Allocated_Dentist
                   + CASE WHEN pp.Last_Allocated_Dentist_Visit_Date IS NULL THEN ' (never seen)'
                          ELSE ' (last seen '
                               + CAST(DATEDIFF(MONTH, pp.Last_Allocated_Dentist_Visit_Date, @Today) AS VARCHAR(10))
                               + ' months ago)' END
                   + ISNULL('. ' + pp.Standard_Payment_Plan, '')
            FROM #plan_patient pp
            JOIN #plan_visit pv ON pv.Tenant_ID = pp.Tenant_ID AND pv.fk_Patient = pp.pk_Patient
            LEFT JOIN #plan_seen_by sb ON sb.Tenant_ID = pp.Tenant_ID AND sb.fk_Patient = pp.pk_Patient
            WHERE pp.Allocated_Dentist IS NOT NULL
              AND (ISNULL(pv.Dentist_Visits, 0) + ISNULL(pv.Hygienist_Visits, 0)) > 0
              AND (pp.Last_Allocated_Dentist_Visit_Date IS NULL
                   OR pp.Last_Allocated_Dentist_Visit_Date < DATEADD(MONTH, -@Plan_Months, @Today))

            UNION ALL
            SELECT 'PAT_NO_DENTIST', p.Tenant_ID, p.pk_Patient, 'Patient',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   p.Last_Appointment_Date, 'Last seen',
                   'No dentist assigned; also listed under Unadopted Patients'
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Dentist_Practitioner_ID IS NULL

            UNION ALL
            SELECT 'PAT_NEVER_SEEN', p.Tenant_ID, p.pk_Patient, 'Patient',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   p.Patient_Created_Date, 'Registered',
                   'Never attended and nothing booked'
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Last_Appointment_Date IS NULL
              AND (p.Next_Appointment_Date IS NULL OR p.Next_Appointment_Date < @Today)

            UNION ALL
            SELECT 'PAT_NO_DOB', p.Tenant_ID, p.pk_Patient, 'Patient',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   p.Last_Appointment_Date, 'Last seen',
                   'No date of birth held'
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Date_Of_Birth IS NULL

            UNION ALL
            SELECT 'PAT_NO_MARKETING_PREF', p.Tenant_ID, p.pk_Patient, 'Patient',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   p.Last_Appointment_Date, 'Last seen',
                   'Never asked for a marketing preference'
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND ISNULL(p.Marketing_Consent, 'Never asked') = 'Never asked'

            -- Recalls ─────────────────────────────────────────────────────────
            UNION ALL
            SELECT 'RECALL_NO_REMINDER', r.Tenant_ID, p.pk_Patient, 'Recall',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   r.Due_Date, 'Recall due',
                   ISNULL(r.Recall_Type, 'Recall') + ' -- '
                   + CAST(r.Days_Overdue AS VARCHAR(20)) + ' days overdue, '
                   + ISNULL(NULLIF(p.Mobile_Phone, ''),
                            ISNULL(NULLIF(p.Email_Address, ''), 'no contact details'))
            FROM Gold.Fact_Recalls r
            JOIN Gold.Dim_Patients p ON p.pk_Patient = r.fk_Patient AND p.Tenant_ID = r.Tenant_ID
            WHERE r.Days_Overdue > 0
              AND ISNULL(r.Is_In_Scope, 0) = 1
              AND ISNULL(r.Is_Reminder_Sent, 0) = 0
              -- You do not chase someone who is already coming in.
              AND (p.Next_Appointment_Date IS NULL OR p.Next_Appointment_Date < @Today)

            -- People ──────────────────────────────────────────────────────────
            UNION ALL
            SELECT 'PRAC_NO_GDC', pr.Tenant_ID, NULL, 'Clinician',
                   pr.Full_Name, CAST(pr.Practitioner_ID AS VARCHAR(100)),
                   NULL, NULL,
                   ISNULL(pr.Role, 'Clinician') + ' -- no GDC number recorded'
            FROM Gold.Dim_Practitioners pr
            WHERE pr.pk_Practitioner > 0 AND pr.Active = 1
              AND (pr.GDC_Number IS NULL OR LTRIM(RTRIM(pr.GDC_Number)) = '')

            -- Treatments ──────────────────────────────────────────────────────
            UNION ALL
            SELECT 'TRT_NO_CODE', tr.Tenant_ID, NULL, 'Treatment',
                   tr.Nomenclature, CAST(tr.Treatment_ID AS VARCHAR(100)),
                   NULL, NULL,
                   'No treatment code -- category '
                   + ISNULL(NULLIF(tr.Treatment_Category_Name, ''), 'also missing')
            FROM Gold.Dim_Treatments tr
            WHERE tr.pk_Treatment > 0
              AND (tr.Treatment_Code IS NULL OR LTRIM(RTRIM(tr.Treatment_Code)) = '')

            UNION ALL
            SELECT 'TRT_NO_CATEGORY', tr.Tenant_ID, NULL, 'Treatment',
                   tr.Nomenclature, CAST(tr.Treatment_ID AS VARCHAR(100)),
                   NULL, NULL,
                   'No category -- code '
                   + ISNULL(NULLIF(tr.Treatment_Code, ''), 'also missing')
            FROM Gold.Dim_Treatments tr
            WHERE tr.pk_Treatment > 0
              AND (tr.Treatment_Category_Name IS NULL
                   OR LTRIM(RTRIM(tr.Treatment_Category_Name)) = '')
        ) x;

        -- ── Full rebuild ─────────────────────────────────────────────────────
        DELETE FROM Gold.Fact_Data_Quality_Detail;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Fact_Data_Quality_Detail (
            pk_Data_Quality_Detail, Tenant_ID, Tenant_Check_Key, Check_Code, Check_Category,
            Check_Name, Severity, Severity_Sort, fk_Patient, Record_Type, Record_Name,
            Record_Reference, Detail_Date, Detail_Label, Detail_Note,
            fk_Date_Next_Appointment, Next_Appointment_Date, Next_Appointment_Days,
            Next_Appointment_Band, Next_Appointment_Band_Sort,
            Dentist_Visits, Hygienist_Visits,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY h.Tenant_ID, c.Display_Order, h.Record_Name),
            h.Tenant_ID,
            CAST(h.Tenant_ID AS VARCHAR(20)) + '|' + h.Check_Code,
            h.Check_Code, c.Check_Category, c.Check_Name, c.Severity, c.Severity_Sort,
            h.fk_Patient, h.Record_Type, h.Record_Name, h.Record_Reference,
            h.Detail_Date, h.Detail_Label, h.Detail_Note,
            -- ── When are they next in? ────────────────────────────────────────────
            -- Computed HERE rather than in each branch: fk_Patient is already on #hits, so one
            -- LEFT JOIN answers it for all fourteen checks at once. Adding it to the branches
            -- would be fourteen chances to write it differently.
            CASE WHEN np.Next_Appointment_Date >= @Today
                 THEN Gold.fn_Get_Date_Key(np.Next_Appointment_Date) END,
            CASE WHEN np.Next_Appointment_Date >= @Today THEN np.Next_Appointment_Date END,
            CASE WHEN np.Next_Appointment_Date >= @Today
                 THEN DATEDIFF(DAY, @Today, np.Next_Appointment_Date) END,
            -- 'Not applicable' and 'None booked' are different answers and must not merge: the
            -- first means the row is not about a patient at all (a clinician, a treatment), the
            -- second means it IS about a patient and there is no way to catch them at the desk.
            -- Numbered for the same reason Severity is: the band is a text column, and plain
            -- text sorts alphabetically -- Later, None booked, Not applicable, Today, Within 7
            -- days -- which is meaningless. The rank in the value makes the slicer and any sort
            -- correct without the model needing a sort-by-column set by hand, which is one more
            -- thing to forget on every republish.
            CASE WHEN h.fk_Patient IS NULL                      THEN '6: Not applicable'
                 WHEN np.Next_Appointment_Date IS NULL
                   OR np.Next_Appointment_Date < @Today         THEN '5: None booked'
                 WHEN np.Next_Appointment_Date = @Today         THEN '1: Today'
                 WHEN np.Next_Appointment_Date <= DATEADD(DAY,  7, @Today) THEN '2: Within 7 days'
                 WHEN np.Next_Appointment_Date <= DATEADD(DAY, 30, @Today) THEN '3: Within 30 days'
                 ELSE '4: Later' END,
            CASE WHEN h.fk_Patient IS NULL                      THEN 6
                 WHEN np.Next_Appointment_Date IS NULL
                   OR np.Next_Appointment_Date < @Today         THEN 5
                 WHEN np.Next_Appointment_Date = @Today         THEN 1
                 WHEN np.Next_Appointment_Date <= DATEADD(DAY,  7, @Today) THEN 2
                 WHEN np.Next_Appointment_Date <= DATEADD(DAY, 30, @Today) THEN 3
                 ELSE 4 END,
            -- Joined on at the end rather than carried through #hits, for the same reason
            -- Next_Appointment is: #hits is one UNION ALL of sixteen branches that must all
            -- project identical columns, and two more would be fourteen extra NULLs to keep
            -- in step. Gated on the check code so the pair cannot leak a count onto a row
            -- where attendance was never the finding.
            CASE WHEN h.Check_Code IN ('PLAN_INACTIVE', 'PLAN_MISALLOCATED') THEN ISNULL(pv.Dentist_Visits, 0) END,
            CASE WHEN h.Check_Code IN ('PLAN_INACTIVE', 'PLAN_MISALLOCATED') THEN ISNULL(pv.Hygienist_Visits, 0) END,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #hits h
        -- Catalogue-gated: a check switched off in Config.Data_Quality_Check must not leave
        -- orphan detail rows behind a count that is no longer on the scorecard.
        JOIN Config.Data_Quality_Check c ON c.Check_Code = h.Check_Code AND c.Is_Active = 1
        LEFT JOIN Gold.Dim_Patients np ON np.pk_Patient = h.fk_Patient
                                      AND np.Tenant_ID  = h.Tenant_ID
        LEFT JOIN #plan_visit pv ON pv.fk_Patient = h.fk_Patient
                                AND pv.Tenant_ID  = h.Tenant_ID;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #hits;
        DROP TABLE #appt;
        DROP TABLE #plan_patient;
        DROP TABLE #plan_visit;
        DROP TABLE #plan_seen_by;

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
