/****** Object:  View [Gold].[vw_Fact_Appointment_Journey] ******/
-- Resolves the appointment-grain pointer table (Gold.Fact_Appointment_Journey)
-- into the MODE-LONG shape the Alluvial consumes: one row per
-- (appointment x mode-it-qualifies-as-a-current-for), with Delay / Next
-- Appointment / Current State as COLUMNS. Because these are columns (not
-- measures), Power BI aggregates server-side and Deneb only ever receives the
-- distinct stage-combinations -- so the visual scales regardless of appointment
-- volume (no per-appointment rows, no 30k data-cap problem).
--
-- The slicer filters [Mode]; site / practitioner / date-range slicers bite via
-- the carried fk_/Start_Time columns.
--
-- Terminal logic (user-directed): when a mode has no "next" of its own type but
-- the patient DOES have another appointment booked, we say which -- e.g. Hygiene
-- Only with an exam booked shows "Non-Hygiene Appointment Booked", not
-- "No Appointment Booked". Enabled by carrying all four pointers.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER VIEW [Gold].[vw_Fact_Appointment_Journey] AS
WITH expanded AS (
    SELECT
        j.Tenant_ID, j.bk_Appointment_ID, j.fk_Patient, j.fk_Practitioner,
        j.fk_Practice_Site, j.fk_Date_Start, j.Start_Time, j.Booking, j.Appointment_Reason,
        j.Is_Cancelled, j.Is_DNA, j.Is_Completed, j.fk_Appointment_Next,
        m.Mode,
        CASE m.Mode
            WHEN 'All Appointments' THEN j.fk_Appointment_Next
            WHEN 'Exclude Hygiene'  THEN j.fk_Appointment_Not_Hygiene
            WHEN 'Exams Only'       THEN j.fk_Appointment_Exam
            WHEN 'Hygiene Only'     THEN j.fk_Appointment_Hygiene
        END AS Mode_Next
    FROM Gold.Fact_Appointment_Journey j
    CROSS JOIN (VALUES ('All Appointments'), ('Exclude Hygiene'), ('Exams Only'), ('Hygiene Only')) m(Mode)
    WHERE m.Mode = 'All Appointments'
       OR (m.Mode = 'Exclude Hygiene' AND j.Appointment_Reason <> 'Hygiene')
       OR (m.Mode = 'Exams Only'      AND j.Appointment_Reason =  'Exam')
       OR (m.Mode = 'Hygiene Only'    AND j.Appointment_Reason =  'Hygiene')
),
keyed AS (
    SELECT e.*,
        -- Non-null only when this mode has no next of its own type. Distinguishes
        -- "nothing booked" from "something of another type booked".
        CASE
            WHEN e.Mode_Next IS NOT NULL THEN NULL
            WHEN e.fk_Appointment_Next IS NULL THEN 'Not Booked'
            WHEN e.Mode = 'Exams Only'      THEN 'Non-Exam Booked'
            WHEN e.Mode = 'Hygiene Only'    THEN 'Non-Hygiene Booked'
            WHEN e.Mode = 'Exclude Hygiene' THEN 'Hygiene Booked'
            ELSE 'Not Booked'
        END AS Terminal_Label
    FROM expanded e
)
SELECT
    e.Tenant_ID, e.bk_Appointment_ID, e.fk_Patient, e.fk_Practitioner,
    e.fk_Practice_Site, e.fk_Date_Start, e.Start_Time, e.Booking, e.Appointment_Reason,
    e.Is_Cancelled, e.Is_DNA, e.Is_Completed, e.Mode,

    -- Delay: banded gap to the mode's next appointment, else the terminal label.
    COALESCE(e.Terminal_Label,
        CASE
            WHEN DATEDIFF(DAY, e.Start_Time, mn.Start_Time) = 0   THEN 'Same Day'
            WHEN DATEDIFF(DAY, e.Start_Time, mn.Start_Time) <= 30  THEN 'Within 1 Month'
            WHEN DATEDIFF(DAY, e.Start_Time, mn.Start_Time) <= 182 THEN 'Within 6 Months'
            WHEN DATEDIFF(DAY, e.Start_Time, mn.Start_Time) <= 365 THEN 'Within 12 Months'
            ELSE 'More than 12 Months'
        END) AS [Delay],

    -- Next Appointment: reason of the mode's next (Emergency shown as Exam), else terminal.
    COALESCE(e.Terminal_Label,
        CASE WHEN mn.Appointment_Reason = 'Emergency' THEN 'Exam' ELSE mn.Appointment_Reason END
        ) AS [Next Appointment],

    -- Current State: Seen Again (next was completed) / BBYL or Booked Later for a
    -- future booking / else recall or lapsed. Uses the any-type pointer so a patient
    -- with another booking isn't mislabelled "Will Not See Again".
    CASE
        WHEN e.Mode_Next IS NOT NULL AND mn.Is_Completed = 1               THEN 'Seen Again'
        WHEN e.Mode_Next IS NOT NULL AND mn.Booking IN ('BBYL', 'Online')  THEN 'BBYL'
        WHEN e.Mode_Next IS NOT NULL                                       THEN 'Booked Later'
        WHEN e.fk_Appointment_Next IS NOT NULL AND an.Is_Completed = 1     THEN 'Seen Again'
        WHEN e.fk_Appointment_Next IS NOT NULL                             THEN 'Booked Later'
        WHEN p.Active = 0                                                  THEN 'Will Not See Again'
        ELSE 'In Recall Process'
    END AS [Current State]
FROM keyed e
LEFT JOIN Gold.Fact_Appointment_Journey mn
    ON mn.Tenant_ID = e.Tenant_ID AND mn.bk_Appointment_ID = e.Mode_Next
LEFT JOIN Gold.Fact_Appointment_Journey an
    ON an.Tenant_ID = e.Tenant_ID AND an.bk_Appointment_ID = e.fk_Appointment_Next
LEFT JOIN Gold.Dim_Patients p
    ON p.Tenant_ID = e.Tenant_ID AND p.pk_Patient = e.fk_Patient;
GO

