-- Seed data for Config.Data_Quality_Check
-- The catalogue of checks shown on Day Book -> Data Quality. The wording is the practice's,
-- not the warehouse's: every Check_Name should read as something a practice manager could act
-- on this afternoon, and What_To_Do should say where in Dentally to go and do it.
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
     'Future appointments booked with a clinician who has left',
     'High', 1,
     'The patient arrives expecting a clinician who is no longer at the practice. Nobody finds out until the day, and the slot was never really available to anyone else.',
     'Reassign each appointment to a current clinician, then contact the patients whose clinician has changed.',
     'FUTURE_APPOINTMENTS', 1, 10),

    ('DIARY_INACTIVE_PATIENT', 'Diary',
     'Future appointments for patients marked inactive',
     'High', 1,
     'Either the patient is still a patient and should not be inactive, or the appointment should not be in the book. One of the two records is wrong.',
     'Open each appointment and decide which is right: reactivate the patient, or cancel the booking.',
     'FUTURE_APPOINTMENTS', 1, 20),

    ('DIARY_NOT_CLOSED', 'Diary',
     'Appointments in the last 90 days still sitting as Pending or Confirmed',
     'Medium', 2,
     'The appointment has been and gone but was never marked completed, cancelled or DNA. Attendance, DNA rate and completed treatment are all understated by exactly these.',
     'Work the list from the oldest forward and set the real outcome on each one.',
     'RECENT_APPOINTMENTS', 1, 30),

    ('DIARY_LEFT_OPEN', 'Diary',
     'Past appointments left at Arrived or In surgery',
     'Medium', 2,
     'The patient was checked in and never checked out, so the appointment never closed. These also inflate average waiting and surgery times.',
     'Close each one off with its real outcome.',
     'RECENT_APPOINTMENTS', 1, 40),

-- Patients ---------------------------------------------------------------------------
    ('PAT_NO_CONTACT', 'Patients',
     'Active patients with no phone number and no email address',
     'High', 1,
     'There is no way to reach these patients at all -- no recall, no reminder, no confirmation. They lapse silently and the practice never learns why.',
     'Collect a contact detail at the next visit, or check whether the record duplicates one that already has them.',
     'ACTIVE_PATIENTS', 1, 50),

    ('PAT_NO_RECALL_DATE', 'Patients',
     'Active patients with no recall date set',
     'High', 1,
     'A patient with no recall date is never called back. They appear on no recall list, so nothing ever flags them as overdue -- they simply stop coming.',
     'Set a dentist and/or hygienist recall interval on each record.',
     'ACTIVE_PATIENTS', 1, 60),

    ('PAT_DORMANT', 'Patients',
     'Active patients not seen for two years with nothing booked',
     'Medium', 2,
     'They still count towards the active list, so patient numbers, revenue per patient and capacity planning are all measured against people who have gone.',
     'Run a reactivation contact, then mark as inactive the ones who do not respond.',
     'ACTIVE_PATIENTS', 1, 70),

    ('PAT_NO_DENTIST', 'Patients',
     'Active patients with no dentist assigned',
     'Medium', 2,
     'Nobody owns the relationship. These patients drop out of per-clinician lists, recall runs and workload figures.',
     'The Unadopted Patients view on this page names them. Assign a dentist on each record -- usually whoever last treated them.',
     'ACTIVE_PATIENTS', 1, 80),

    ('PAT_NEVER_SEEN', 'Patients',
     'Active patients who have never attended and have nothing booked',
     'Medium', 2,
     'Usually a registration that never converted, or a duplicate created at the desk. Either way they inflate the active patient count.',
     'Check for a duplicate record, then either book them in or mark them inactive.',
     'ACTIVE_PATIENTS', 1, 90),

    ('PAT_NO_DOB', 'Patients',
     'Active patients with no date of birth',
     'Medium', 2,
     'Without a date of birth the record cannot be read as an adult or a child, which affects NHS banding, recall intervals and consent.',
     'Capture the date of birth at the next visit.',
     'ACTIVE_PATIENTS', 1, 100),

-- SEEDED INACTIVE (Is_Active = 0), and it must stay that way until Silver is fixed.
-- Dentally holds marketing as THREE states -- yes, no, never asked. Silver.Patients.Marketing_Opt_In
-- is a BIT, so "no" and "never asked" both land as 0, and Gold then maps 0 to NULL. On tenant 100
-- that silently merges 170 patients who gave an answer with 27,491 who were never asked.
-- The check would therefore report "no preference recorded" for people who recorded one -- on a
-- consent field, which is the one place that distinction carries legal weight. It would also read
-- 97.7%, so as a finding it is noise a practice cannot act on.
-- Re-enable it once Silver preserves the third state; the counting branch in the load proc is
-- already there and correct.
    ('PAT_NO_MARKETING_PREF', 'Patients',
     'Active patients with no marketing preference recorded',
     'Low', 3,
     'With no recorded preference they cannot safely be included in any marketing, so the reachable audience is far smaller than the patient list suggests.',
     'Ask at the next visit, or run a one-off preference request to those who can be contacted.',
     'ACTIVE_PATIENTS', 0, 110),

-- Recalls ----------------------------------------------------------------------------
    ('RECALL_NO_REMINDER', 'Recalls',
     'Overdue recalls where no reminder has ever been sent',
     'High', 1,
     'These patients are overdue and have not been asked once. Unlike an ignored reminder, this is the practice failing to make contact rather than the patient declining.',
     'Send the first reminder, and check why the recall run skipped them -- usually a missing contact detail or recall method.',
     'OVERDUE_RECALLS', 1, 120),

-- People -----------------------------------------------------------------------------
    ('PRAC_NO_GDC', 'People',
     'Active clinicians with no GDC number recorded',
     'Medium', 2,
     'The GDC number is the registration check. Missing ones turn a compliance audit into a manual exercise.',
     'Add the GDC number to each clinician record.',
     'ACTIVE_PRACTITIONERS', 1, 130),

-- Treatments -------------------------------------------------------------------------
    ('TRT_NO_CODE', 'Treatments',
     'Treatments with no treatment code',
     'Medium', 2,
     'Uncoded treatments cannot be grouped, priced or claimed consistently, and they fall out of every treatment mix breakdown.',
     'Add a code to each treatment in the treatment list.',
     'TREATMENTS', 1, 140),

    ('TRT_NO_CATEGORY', 'Treatments',
     'Treatments with no category',
     'Low', 3,
     'Uncategorised treatments report as a single unattributed bucket, so the treatment mix picture is incomplete.',
     'Set a category on each treatment in the treatment list.',
     'TREATMENTS', 1, 150);
GO
