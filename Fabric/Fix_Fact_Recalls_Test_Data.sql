-- Fix_Fact_Recalls_Test_Data.sql
-- Rebuilds Gold.Fact_Recalls for T11-T14 with realistic recall lifecycle data.
--
-- Safe pattern: build into #staged first, verify row count, THEN delete + insert.
-- Due date source priority: Dentist_Recall_Date > Last_Exam_Date+6m > synthetic spread.
-- Synthetic spread uses pk_Patient % 32 to give a 32-month window centred on today,
-- so every patient gets a deterministic but varied due date.

DECLARE @today         DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @epoch         DATE = '19991231';
DECLARE @reminder_lead INT  = 42;    -- first reminder: 6 weeks before due
DECLARE @second_lead   INT  = 14;    -- second reminder: 2 weeks before due (overdue only)
DECLARE @cutoff        DATE = DATEADD(MONTH, -24, @today);

-- ── Stage the recalls ────────────────────────────────────────────────────────
SELECT
    dp.Tenant_ID,
    'REC-' + CAST(dp.pk_Patient AS VARCHAR(20))                        AS bk_Recall_ID,
    dp.pk_Patient,

    -- Due date: use actual recall date if set, else last exam + 6m, else synthetic spread
    CAST(COALESCE(
        dp.Dentist_Recall_Date,
        DATEADD(MONTH, 6, dp.Last_Exam_Date),
        DATEADD(MONTH, 6, dp.Last_Appointment_Date),
        DATEADD(DAY, (ABS(CHECKSUM(dp.pk_Patient)) % 960) - 720, @today)
    ) AS DATE)                                                         AS Due_Date

INTO #staged_due
FROM Gold.Dim_Patients dp
WHERE dp.Tenant_ID IN (11, 12, 13, 14)
  AND (
      dp.Dentist_Recall_Date   IS NOT NULL
   OR dp.Last_Exam_Date        IS NOT NULL
   OR dp.Last_Appointment_Date IS NOT NULL
   OR 1 = 1   -- synthetic fallback always fires
  );

-- Remove rows where the derived due date is older than 24 months (stale, would be deleted by Dentally)
DELETE FROM #staged_due WHERE Due_Date < @cutoff;

-- ── Safety check ─────────────────────────────────────────────────────────────
DECLARE @staged INT = (SELECT COUNT(*) FROM #staged_due);
PRINT 'Rows staged: ' + CAST(@staged AS VARCHAR(20));
IF @staged = 0
BEGIN
    DROP TABLE #staged_due;
    RAISERROR('No rows staged — Gold.Dim_Patients may have no T11-14 patients. Aborting.', 16, 1);
    RETURN;
END

-- ── Delete existing and insert ───────────────────────────────────────────────
DELETE FROM Gold.Fact_Recalls WHERE Tenant_ID IN (11, 12, 13, 14);

INSERT INTO Gold.Fact_Recalls (
    Tenant_ID, bk_Recall_ID, fk_Patient,
    fk_Date_Due, fk_Date_Run,
    fk_Date_First_Reminder, fk_Date_Second_Reminder, fk_Date_Last_Reminded,
    Appointment_ID,
    Recall_Type, Recall_Method, Status,
    Workflow_Status, Workflow_Stage_ID,
    First_Reminder_Type, Second_Reminder_Type, Latest_Reminder_Type,
    Times_Contacted, Due_Date, Run_Date, Days_Overdue,
    DW_Created_At, DW_Updated_At
)
SELECT
    s.Tenant_ID,
    s.bk_Recall_ID,
    s.pk_Patient,

    DATEDIFF(d, @epoch, s.Due_Date)                                    AS fk_Date_Due,
    DATEDIFF(d, @epoch, DATEADD(d, -3, s.Due_Date))                    AS fk_Date_Run,

    -- First reminder sent when within 6 weeks of due date
    CASE WHEN DATEADD(d, -@reminder_lead, s.Due_Date) <= @today
         THEN DATEDIFF(d, @epoch, DATEADD(d, -@reminder_lead, s.Due_Date))
         ELSE NULL END                                                  AS fk_Date_First_Reminder,

    -- Second reminder: only for overdue recalls, 2 weeks before due
    CASE WHEN s.Due_Date < @today
              AND DATEADD(d, -@second_lead, s.Due_Date) <= @today
         THEN DATEDIFF(d, @epoch, DATEADD(d, -@second_lead, s.Due_Date))
         ELSE NULL END                                                  AS fk_Date_Second_Reminder,

    -- Last reminded = most recent of the above
    CASE WHEN s.Due_Date < @today
              AND DATEADD(d, -@second_lead, s.Due_Date) <= @today
         THEN DATEDIFF(d, @epoch, DATEADD(d, -@second_lead, s.Due_Date))
         WHEN DATEADD(d, -@reminder_lead, s.Due_Date) <= @today
         THEN DATEDIFF(d, @epoch, DATEADD(d, -@reminder_lead, s.Due_Date))
         ELSE NULL END                                                  AS fk_Date_Last_Reminded,

    -- ~40% of in-scope patients (reminder sent) marked as booked via recall workflow
    CASE WHEN DATEADD(d, -@reminder_lead, s.Due_Date) <= @today
              AND ABS(CHECKSUM(s.pk_Patient)) % 10 < 4
         THEN 'APT-' + CAST(s.pk_Patient AS VARCHAR(20))
         ELSE NULL END                                                  AS Appointment_ID,

    'Dentist'                                                           AS Recall_Type,
    'sms'                                                               AS Recall_Method,
    CASE WHEN s.Due_Date < @today THEN 'overdue' ELSE 'pending' END    AS Status,

    NULL AS Workflow_Status,
    NULL AS Workflow_Stage_ID,

    CASE WHEN DATEADD(d, -@reminder_lead, s.Due_Date) <= @today THEN 'sms' ELSE NULL END
                                                                        AS First_Reminder_Type,
    CASE WHEN s.Due_Date < @today
              AND DATEADD(d, -@second_lead, s.Due_Date) <= @today
         THEN 'sms' ELSE NULL END                                       AS Second_Reminder_Type,
    CASE WHEN s.Due_Date < @today
              AND DATEADD(d, -@second_lead, s.Due_Date) <= @today THEN 'sms'
         WHEN DATEADD(d, -@reminder_lead, s.Due_Date) <= @today        THEN 'sms'
         ELSE NULL END                                                  AS Latest_Reminder_Type,

    CASE WHEN s.Due_Date < @today
              AND DATEADD(d, -@second_lead, s.Due_Date) <= @today THEN 2
         WHEN DATEADD(d, -@reminder_lead, s.Due_Date) <= @today        THEN 1
         ELSE 0 END                                                     AS Times_Contacted,

    s.Due_Date,
    DATEADD(d, -3, s.Due_Date)                                         AS Run_Date,
    CASE WHEN s.Due_Date < @today
         THEN DATEDIFF(d, s.Due_Date, @today) ELSE 0 END               AS Days_Overdue,

    SYSUTCDATETIME(),
    SYSUTCDATETIME()

FROM #staged_due s
INNER JOIN Gold.Dim_Patients dp
    ON  dp.pk_Patient = s.pk_Patient
    AND dp.Tenant_ID  = s.Tenant_ID;

DROP TABLE #staged_due;

-- ── Distribution check ───────────────────────────────────────────────────────
SELECT
    Tenant_ID,
    Status,
    COUNT(*)                                                               AS Recalls,
    SUM(CASE WHEN fk_Date_First_Reminder IS NOT NULL THEN 1 ELSE 0 END)   AS With_Reminder,
    SUM(CASE WHEN Appointment_ID         IS NOT NULL THEN 1 ELSE 0 END)   AS Booked_Via_Recall,
    MIN(Due_Date)                                                          AS Earliest_Due,
    MAX(Due_Date)                                                          AS Latest_Due
FROM Gold.Fact_Recalls
WHERE Tenant_ID IN (11, 12, 13, 14)
GROUP BY Tenant_ID, Status
ORDER BY Tenant_ID, Status;
