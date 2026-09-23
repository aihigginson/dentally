--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Data_Quality_Detail] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Data_Quality_Detail
--  Author           :  AIH
--  Initial Date     :  23/09/2026
--  History          :
--    *01     23/09/2026  AIH  Initial Release (V176)
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

        DECLARE @Today          DATE = CAST(SYSUTCDATETIME() AS DATE);
        DECLARE @Recent_Days    INT  = 90;
        DECLARE @Dormant_Months INT  = 24;

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

            UNION ALL
            SELECT 'PAT_DORMANT', p.Tenant_ID, p.pk_Patient, 'Patient',
                   p.Full_Name, CAST(p.Patient_ID AS VARCHAR(100)),
                   p.Last_Appointment_Date, 'Last seen',
                   'Lifetime value £' + CAST(CAST(ISNULL(p.Total_Paid, 0) AS INT) AS VARCHAR(20))
                   + ISNULL(' -- ' + NULLIF(p.Email_Address, ''), '')
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Last_Appointment_Date < DATEADD(MONTH, -@Dormant_Months, @Today)
              AND (p.Next_Appointment_Date IS NULL OR p.Next_Appointment_Date <= @Today)

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
              AND (p.Next_Appointment_Date IS NULL OR p.Next_Appointment_Date <= @Today)

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
            CASE WHEN h.fk_Patient IS NULL                      THEN 'Not applicable'
                 WHEN np.Next_Appointment_Date IS NULL
                   OR np.Next_Appointment_Date < @Today         THEN 'None booked'
                 WHEN np.Next_Appointment_Date = @Today         THEN 'Today'
                 WHEN np.Next_Appointment_Date <= DATEADD(DAY,  7, @Today) THEN 'Within 7 days'
                 WHEN np.Next_Appointment_Date <= DATEADD(DAY, 30, @Today) THEN 'Within 30 days'
                 ELSE 'Later' END,
            CASE WHEN h.fk_Patient IS NULL                      THEN 6
                 WHEN np.Next_Appointment_Date IS NULL
                   OR np.Next_Appointment_Date < @Today         THEN 5
                 WHEN np.Next_Appointment_Date = @Today         THEN 1
                 WHEN np.Next_Appointment_Date <= DATEADD(DAY,  7, @Today) THEN 2
                 WHEN np.Next_Appointment_Date <= DATEADD(DAY, 30, @Today) THEN 3
                 ELSE 4 END,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #hits h
        -- Catalogue-gated: a check switched off in Config.Data_Quality_Check must not leave
        -- orphan detail rows behind a count that is no longer on the scorecard.
        JOIN Config.Data_Quality_Check c ON c.Check_Code = h.Check_Code AND c.Is_Active = 1
        LEFT JOIN Gold.Dim_Patients np ON np.pk_Patient = h.fk_Patient
                                      AND np.Tenant_ID  = h.Tenant_ID;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #hits;
        DROP TABLE #appt;

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
