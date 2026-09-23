-- Seed data for Config.Data_Quality_Check
-- The catalogue of checks shown on Day Book -> Data Quality. The wording is the practice's,
-- not the warehouse's: every Check_Name should read as something a practice manager could act
-- on this afternoon, and What_To_Do should say where in Dentally to go and do it.
--
-- Check_Name is a LABEL, not a sentence: short Title Case, matching the register in
-- Config.Metric_Definitions ("Lapsed Patients", "Recalls Overdue Not Sent"). The
-- explanation lives in Why_It_Matters, which is where a reader who wants it looks.
--
-- Severity is stored as '1: High' / '2: Medium' / '3: Low' so that clicking the column in
-- the report sorts by urgency. Plain text sorts alphabetically -- High, Low, Medium -- which
-- buries the least urgent band in the middle.
--
-- Every Check_Code here MUST have a matching branch in Gold.usp_Load_Aggregate_Data_Quality.
-- A code with no branch silently reports 0, which reads as a passing check -- the worst
-- failure this table has.
DELETE FROM [Config].[Data_Quality_Check];
GO

INSERT INTO [Config].[Data_Quality_Check]
    ([Check_Code], [Check_Category], [Check_Name], [Severity], [Severity_Sort],
     [Why_It_Matters], [What_To_Do], [Population_Key], [Is_Active], [Display_Order])
VALUES
-- Diary ------------------------------------------------------------------------------
    ('DIARY_LEAVER_BOOKED', 'Diary',
     'Booked with a Departed Clinician',
     '1: High', 1,
     'The patient arrives expecting a clinician who is no longer at the practice. Nobody finds out until the day, and the slot was never really available to anyone else.',
     'Reassign each appointment to a current clinician, then contact the patients whose clinician has changed.',
     'FUTURE_APPOINTMENTS', 1, 10),

    ('DIARY_INACTIVE_PATIENT', 'Diary',
     'Booked but Marked Inactive',
     '1: High', 1,
     'Either the patient is still a patient and should not be inactive, or the appointment should not be in the book. One of the two records is wrong.',
     'Open each appointment and decide which is right: reactivate the patient, or cancel the booking.',
     'FUTURE_APPOINTMENTS', 1, 20),

    ('DIARY_NOT_CLOSED', 'Diary',
     'Appointments Not Closed Off',
     '2: Medium', 2,
     'The appointment has been and gone but was never marked completed, cancelled or DNA. Attendance, DNA rate and completed treatment are all understated by exactly these.',
     'Work the list from the oldest forward and set the real outcome on each one.',
     'RECENT_APPOINTMENTS', 1, 30),

    ('DIARY_LEFT_OPEN', 'Diary',
     'Left Arrived or In Surgery',
     '2: Medium', 2,
     'The patient was checked in and never checked out, so the appointment never closed. These also inflate average waiting and surgery times.',
     'Close each one off with its real outcome.',
     'RECENT_APPOINTMENTS', 1, 40),

-- Patients ---------------------------------------------------------------------------
    ('PAT_NO_CONTACT', 'Patients',
     'No Contact Details',
     '1: High', 1,
     'There is no way to reach these patients at all -- no recall, no reminder, no confirmation. They lapse silently and the practice never learns why.',
     'Collect a contact detail at the next visit, or check whether the record duplicates one that already has them.',
     'ACTIVE_PATIENTS', 1, 50),

    ('PAT_NO_RECALL_DATE', 'Patients',
     'No Recall Date',
     '1: High', 1,
     'A patient with no recall date is never called back. They appear on no recall list, so nothing ever flags them as overdue -- they simply stop coming. Patients who already have an appointment booked are excluded: they are coming in regardless.',
     'Set a dentist and/or hygienist recall interval on each record.',
     'ACTIVE_PATIENTS', 1, 60),

    ('PAT_DORMANT', 'Patients',
     'Dormant Two Years',
     '2: Medium', 2,
     'They still count towards the active list, so patient numbers, revenue per patient and capacity planning are all measured against people who have gone.',
     'Run a reactivation contact, then mark as inactive the ones who do not respond.',
     'ACTIVE_PATIENTS', 1, 70),

    ('PAT_NO_DENTIST', 'Patients',
     'No Dentist Assigned',
     '2: Medium', 2,
     'Nobody owns the relationship. These patients drop out of per-clinician lists, recall runs and workload figures.',
     'The Unadopted Patients view on this page names them. Assign a dentist on each record -- usually whoever last treated them.',
     'ACTIVE_PATIENTS', 1, 80),

    ('PAT_NEVER_SEEN', 'Patients',
     'Never Attended',
     '2: Medium', 2,
     'Usually a registration that never converted, or a duplicate created at the desk. Either way they inflate the active patient count.',
     'Check for a duplicate record, then either book them in or mark them inactive.',
     'ACTIVE_PATIENTS', 1, 90),

    ('PAT_NO_DOB', 'Patients',
     'No Date of Birth',
     '2: Medium', 2,
     'Without a date of birth the record cannot be read as an adult or a child, which affects NHS banding, recall intervals and consent.',
     'Capture the date of birth at the next visit.',
     'ACTIVE_PATIENTS', 1, 100),

-- Re-enabled by V173. Silver.Patients.Marketing_Opt_In now preserves Dentally's three states
-- (true / false / absent) instead of folding "no" in with "never asked", and Gold maps them to
-- 'Opted in' / 'Opted out' / NULL. So Marketing_Consent IS NULL now means what this check says
-- it means: nobody ever asked. Before V173 it also swept up everyone who had answered no.
    ('PAT_NO_MARKETING_PREF', 'Patients',
     'No Marketing Preference',
     '3: Low', 3,
     'With no recorded preference they cannot safely be included in any marketing, so the reachable audience is far smaller than the patient list suggests.',
     'Ask at the next visit, or run a one-off preference request to those who can be contacted.',
     'ACTIVE_PATIENTS', 1, 110),

-- Recalls ----------------------------------------------------------------------------
    ('RECALL_NO_REMINDER', 'Recalls',
     'Recalls Never Chased',
     '1: High', 1,
     'These patients are overdue and have not been asked once. Unlike an ignored reminder, this is the practice failing to make contact rather than the patient declining. Patients who already have an appointment booked are excluded: there is nothing to chase.',
     'Send the first reminder, and check why the recall run skipped them -- usually a missing contact detail or recall method.',
     'OVERDUE_RECALLS', 1, 120),

-- People -----------------------------------------------------------------------------
    ('PRAC_NO_GDC', 'People',
     'No GDC Number',
     '2: Medium', 2,
     'The GDC number is the registration check. Missing ones turn a compliance audit into a manual exercise.',
     'Add the GDC number to each clinician record.',
     'ACTIVE_PRACTITIONERS', 1, 130),

-- Treatments -------------------------------------------------------------------------
    ('TRT_NO_CODE', 'Treatments',
     'No Treatment Code',
     '2: Medium', 2,
     'Uncoded treatments cannot be grouped, priced or claimed consistently, and they fall out of every treatment mix breakdown.',
     'Add a code to each treatment in the treatment list.',
     'TREATMENTS', 1, 140),

    ('TRT_NO_CATEGORY', 'Treatments',
     'No Treatment Category',
     '3: Low', 3,
     'Uncategorised treatments report as a single unattributed bucket, so the treatment mix picture is incomplete.',
     'Set a category on each treatment in the treatment list.',
     'TREATMENTS', 1, 150);
GO
