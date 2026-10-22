--------------------------------------------------------------------
--  Data   :  Gold.Dim_Patient_Status
--  Author :  AIH
--  Purpose:  Seed the patient lifecycle ladder. DELETE + INSERT rather than a MERGE: the
--            rows are fixed reference data with hardcoded keys, so a full replace is both
--            idempotent and the only way a renamed status reaches the model.
--
--            ==> THE KEYS ARE PART OF THE CONTRACT. <== They are written into
--            Gold.Dim_Patients.fk_Patient_Status and bound by report filters. Add a rung by
--            taking the next free number; never renumber an existing one.
--
--            The DERIVATION PRECEDENCE lives in Gold.usp_Load_Dim_Patients and is NOT the
--            Sort_Order below. Archived (10) is tested FIRST, ahead of both lapsed rungs:
--            a patient with no attendance history was never lost, because they were never
--            had. At the live tenant that moves 19,512 patients out of the lapsed figures.
--
--  History:
--    *01     22/10/2026  AIH V229: initial release.
--------------------------------------------------------------------
DELETE FROM [Gold].[Dim_Patient_Status];
GO

INSERT INTO [Gold].[Dim_Patient_Status]
    ([pk_Patient_Status], [Status_Code], [Status_Name], [Status_Group],
     [Status_Description],
     [Sort_Order], [Is_Active], [Is_At_Risk], [Is_Lost], [Is_Never_Attended],
     [Is_Reportable], [Patient_Status_Count], [DW_Created_At], [DW_Updated_At])
-- INSERT ... SELECT over a table value constructor. Patient_Status_Count and the two DW
-- stamps are NOT NULL with no default, so they have to be supplied by the INSERT itself --
-- a follow-up UPDATE never runs, because the INSERT fails first. Stating them once here
-- beats repeating them on every row.
SELECT v.[pk_Patient_Status], v.[Status_Code], v.[Status_Name], v.[Status_Group],
       v.[Status_Description],
       v.[Sort_Order], v.[Is_Active], v.[Is_At_Risk], v.[Is_Lost], v.[Is_Never_Attended],
       v.[Is_Reportable], 1, SYSUTCDATETIME(), SYSUTCDATETIME()
FROM (VALUES
    (-1, 'UNKNOWN', 'Unknown', 'Unknown',
        'Placeholder so a patient mid-load, or one whose status could not be derived, still joins. A fk of -1 hides under All and blanks every tile under a selection, so the row has to exist.',
        0, 0, 0, 0, 0, 1),
    (1, 'ACTIVE_BOOKED', 'Active with Appointment', 'Active',
        'Has a future appointment that has not been cancelled. Nothing to do.',
        1, 1, 0, 0, 0, 1),
    (2, 'ACTIVE_RECALL_FUTURE', 'Active, Recall Not Yet Due', 'Active',
        'No appointment booked, but their recall date has not arrived yet. Nothing to do yet.',
        2, 1, 0, 0, 0, 1),
    (3, 'ACTIVE_NO_RECALL', 'Active, No Recall Set', 'Active',
        'Attending, but carries no dentist recall date, so nothing will ever prompt them to come back. An administrative gap rather than a patient behaviour.',
        3, 1, 0, 0, 0, 1),
    (4, 'RECALL_OVERDUE_UNSENT', 'Recall Overdue, Not Sent', 'Active',
        'Recall date has passed and no reminder has gone out. The practice has not asked them yet, so their silence means nothing. The most actionable rung on the ladder.',
        4, 1, 0, 0, 0, 1),
    (5, 'RECALL_SENT_NO_REPLY_LT2M', 'Recall Sent, No Response Under 2 Months', 'Active',
        'Reminded and not yet booked, within the last two months. Normal; most people take a few weeks to respond.',
        5, 1, 0, 0, 0, 1),
    (6, 'RECALL_SENT_NO_REPLY_GT2M', 'Recall Unanswered 2m+', 'Recall Unanswered',
        'NOT the same as PBI.[_Patient At Risk], which is a wider operational worklist counting one row per reason (recall due, cancelled not rebooked, open course) and runs about 713 patients where this rung runs 1,167. Two things called At Risk on one report is how a practice stops trusting both. Asked to come back more than two months ago and has not. Still on the list, but this is the last rung before lapsing and the only one where intervention still works.',
        6, 0, 1, 0, 0, 1),
    (7, 'LAPSED_NO_VISIT_24M', 'Lapsed, No Visit in 24 Months', 'Lost',
        'Two years since their last appointment with nothing booked. Derived, not a Dentally flag: the practice has not marked them inactive, they have simply gone.',
        7, 0, 0, 1, 0, 1),
    (8, 'LAPSED_SET_INACTIVE', 'Lapsed, Set Inactive in Dentally', 'Lost',
        'Marked inactive at source. Someone at the practice made this decision, so it is not evidence of patient behaviour: it includes duplicates, deceased patients and registrations that were tidied away.',
        8, 0, 0, 1, 0, 1),
    (9, 'NEVER_SEEN_NO_APPT', 'Never Seen, No Appointment', 'Never Attended',
        'Registered, never attended, nothing booked, and still active at source. NOT counted as lost, because a patient who never arrived was never had. A referral or an enquiry that did not convert.',
        9, 0, 0, 0, 1, 1),
    (10, 'ARCHIVED_NO_HISTORY', 'Archived, No Attendance History', 'Archived',
        'No completed appointment, no invoice and no payment anywhere in the warehouse. These are overwhelmingly pre-migration records: the practice brought its patient list but only part of its appointment history, so anyone who stopped attending before the first appointment on file is indistinguishable from someone who never came. Excluded from every regular figure via Is_Reportable = 0 -- counting them as lapsed overstates patient loss by an order of magnitude.',
        10, 0, 0, 0, 1, 0)
) AS v ([pk_Patient_Status], [Status_Code], [Status_Name], [Status_Group],
        [Status_Description],
        [Sort_Order], [Is_Active], [Is_At_Risk], [Is_Lost], [Is_Never_Attended],
        [Is_Reportable]);
GO

-- Exactly one rung may be At Risk, exactly two may be Lost, and exactly one may be
-- unreportable. Every retention figure in the product is built on those flags, so a seed
-- that silently widens any of them changes every lapsed number without touching a measure.
DECLARE @r INT, @l INT, @a INT, @e VARCHAR(4000);
SELECT @r = SUM(CAST([Is_At_Risk] AS INT)),
       @l = SUM(CAST([Is_Lost] AS INT)),
       @a = SUM(CASE WHEN [Is_Reportable] = 0 THEN 1 ELSE 0 END)
FROM   [Gold].[Dim_Patient_Status];
IF @r <> 1 OR @l <> 2 OR @a <> 1
BEGIN
    SET @e = 'Dim_Patient_Status seed FAILED: At Risk ' + CAST(@r AS VARCHAR(10))
           + ' (expected 1), Lost ' + CAST(@l AS VARCHAR(10)) + ' (expected 2), '
           + 'unreportable ' + CAST(@a AS VARCHAR(10)) + ' (expected 1).';
    THROW 50580, @e, 1;
END;
GO
