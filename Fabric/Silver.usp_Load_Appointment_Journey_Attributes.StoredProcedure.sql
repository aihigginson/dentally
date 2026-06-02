--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Appointment_Journey_Attributes] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Appointment_Journey_Attributes
--  Author           :  AIH
--  Initital Date    :  13/05/2026
--  History          :
--    *01     13/05/2026  AIH Initial Release
--    *02     13/05/2026  AIH Fix datetime casting (strip tz suffix); Next_Visit defaults;
--                            Emergency next visit treated as Exam; Recall Sent via First_Reminder_Sent_At
--    *03     15/05/2026  AIH Fix all four Sankey columns
--    *04     20/05/2026  AIH Column naming convention fixes (ID/_ID, API)
--                            Booking: distinguish BBYL vs Online (prev_appt date match);
--                            add Referral using Silver.Patient_Referrals.Created_At;
--                            This_Visit: Review appointments now generated upstream;
--                            Next_Visit: changed nxt to show chronological next visit;
--                            Future_Appt: separate active_bkg apply;
--                            rename Other Booked -> Treatment Booked
--    *06     31/05/2026  AIH BBYL fix: add Pending_DT to #appts; use Pending_DT (not Created_DT)
--                            for BBYL date check — Created_At is never populated in source data
--    *05     31/05/2026  AIH Rename SP to usp_Load_Appointment_Journey_Attributes;
--                            rename table to Silver.Appointment_Journey_Attributes;
--                            rename This_Visit->Appointment_Reason, Next_Visit->Next_Appointment,
--                            Future_Appointment->Current_State; add Delay phase (banded gap
--                            to next appointment); convert CTEs to temp tables;
--                            Next_Appointment NULL -> 'No Future Appointment' (was 'Exam'/'Closed')
--  To Run           :   DECLARE  @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Silver.usp_Load_Appointment_Journey_Attributes @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Appointment_Journey_Attributes]    Script Date: 31/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Appointment_Journey_Attributes]
GO
CREATE PROCEDURE [Silver].[usp_Load_Appointment_Journey_Attributes]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       smallint         = 1
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
    SET NOCOUNT ON;
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        -- Full recompute: delete all derived rows then re-derive from source tables.

        DROP TABLE IF EXISTS #appts;
        DROP TABLE IF EXISTS #first_attended;
        DROP TABLE IF EXISTS #referrals;
        DROP TABLE IF EXISTS #latest_recall;

        -- Cast varchar date columns once for reuse throughout.
        -- LEFT(..., 23) strips any timezone suffix (e.g. +00:00) before casting to datetime2(3).
        SELECT
            a.Tenant_ID,
            a.Appointment_ID,
            a.Patient_ID,
            a.Reason,
            a.Booked_Via_API,
            TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time),        ''), 23) AS datetime2(3)) AS Start_DT,
            TRY_CAST(LEFT(NULLIF(TRIM(a.Completed_At),      ''), 23) AS datetime2(3)) AS Completed_DT,
            TRY_CAST(LEFT(NULLIF(TRIM(a.Cancelled_At),      ''), 23) AS datetime2(3)) AS Cancelled_DT,
            TRY_CAST(LEFT(NULLIF(TRIM(a.Did_Not_Attend_At), ''), 23) AS datetime2(3)) AS DNA_DT,
            TRY_CAST(LEFT(NULLIF(TRIM(a.Created_At),        ''), 23) AS datetime2(3)) AS Created_DT,
            TRY_CAST(LEFT(NULLIF(TRIM(a.Pending_At),        ''), 23) AS datetime2(3)) AS Pending_DT
        INTO #appts
        FROM Silver.Appointments a
        WHERE a.Appointment_ID IS NOT NULL;

        -- Lowest Appointment_ID among attended appointments per patient; used to flag 'New' channel.
        SELECT Tenant_ID, Patient_ID, MIN(Appointment_ID) AS First_Appt_ID
        INTO #first_attended
        FROM #appts
        WHERE Completed_DT IS NOT NULL
        GROUP BY Tenant_ID, Patient_ID;

        -- Earliest referral date per patient; used to identify the first appointment as 'Referral'.
        SELECT Tenant_ID, Patient_ID,
               MIN(COALESCE(Created_At, DW_Created_At)) AS Earliest_Referral_DT
        INTO #referrals
        FROM Silver.Patient_Referrals
        GROUP BY Tenant_ID, Patient_ID;

        -- Latest recall record per patient.
        SELECT Tenant_ID, Patient_ID, Due_Date, First_Reminder_Sent_At
        INTO #latest_recall
        FROM (
            SELECT
                Tenant_ID, Patient_ID, Due_Date, First_Reminder_Sent_At,
                ROW_NUMBER() OVER (
                    PARTITION BY Tenant_ID, Patient_ID
                    ORDER BY Due_Date DESC, DW_Created_At DESC
                ) AS rn
            FROM Silver.Recalls
        ) r
        WHERE rn = 1;

        DELETE FROM [Silver].[Appointment_Journey_Attributes];
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO [Silver].[Appointment_Journey_Attributes] (
            [Tenant_ID], [Appointment_ID],
            [Booking], [Appointment_Reason], [Delay], [Next_Appointment], [Current_State],
            [DW_Created_At], [DW_Updated_At]
        )
        SELECT
            a.Tenant_ID,
            a.Appointment_ID,

            -- Booking: how the patient came to book this appointment (priority order).
            -- BBYL = booked via API on the same date as their previous completed visit.
            -- Online = booked via API on any other date (patient self-booked remotely).
            CASE
                WHEN ref_appt.Appointment_ID = a.Appointment_ID THEN 'Referral'
                WHEN fa.First_Appt_ID        = a.Appointment_ID THEN 'New'
                WHEN a.Booked_Via_API = 1
                     AND prev_appt.Prev_Date IS NOT NULL
                     AND CAST(a.Pending_DT AS DATE) = prev_appt.Prev_Date THEN 'BBYL'
                WHEN a.Booked_Via_API = 1                                  THEN 'Online'
                ELSE 'Reception'
            END AS Booking,

            -- Appointment_Reason: mapped category if known, otherwise raw reason text, otherwise NULL.
            COALESCE(arm_this.Category, NULLIF(TRIM(a.Reason), '')) AS Appointment_Reason,

            -- Delay: banded gap between this appointment and the next non-cancelled/non-DNA appointment.
            CASE
                WHEN nxt.Appointment_ID IS NULL                               THEN 'No Future Appointment'
                WHEN DATEDIFF(DAY, a.Start_DT, nxt.Start_DT) = 0             THEN 'Same Day'
                WHEN DATEDIFF(DAY, a.Start_DT, nxt.Start_DT) <= 30           THEN 'Within 1 Month'
                WHEN DATEDIFF(DAY, a.Start_DT, nxt.Start_DT) <= 182          THEN 'Within 6 Months'
                WHEN DATEDIFF(DAY, a.Start_DT, nxt.Start_DT) <= 365          THEN 'Within 12 Months'
                ELSE                                                           'More than 12 Months'
            END AS Delay,

            -- Next_Appointment: category of the chronologically next non-cancelled/non-DNA appointment.
            -- Completed past appointments are included so the column reflects what the patient actually did next.
            -- Emergency bookings are unplanned so treated as if no appointment (defaults to Exam).
            CASE
                WHEN nxt.Appointment_ID IS NULL                                                            THEN 'No Future Appointment'
                WHEN COALESCE(arm_nxt.Category, NULLIF(TRIM(nxt.Reason), '')) = 'Emergency'               THEN 'Exam'
                ELSE COALESCE(arm_nxt.Category, NULLIF(TRIM(nxt.Reason), ''))
            END AS Next_Appointment,

            -- Current_State: post-visit status based on active (uncompleted) future bookings.
            -- Seen Again = a completed visit has occurred since this one.
            -- BBYL / Treatment Booked = an active future booking exists.
            -- Recall categories = no active booking; recall record drives expectation.
            CASE
                WHEN seen_again.Appointment_ID IS NOT NULL                                         THEN 'Seen Again'
                WHEN active_bkg.Appointment_ID IS NOT NULL AND active_bkg.Booked_Via_API = 1      THEN 'BBYL'
                WHEN active_bkg.Appointment_ID IS NOT NULL                                         THEN 'Treatment Booked'
                WHEN pat.Active = 0                                                                THEN 'Will Not See Again'
                WHEN lr.First_Reminder_Sent_At IS NOT NULL                                         THEN 'Recall Sent'
                WHEN lr.Due_Date < CAST(SYSDATETIME() AS DATE)                                     THEN 'Recall Overdue'
                WHEN lr.Due_Date IS NOT NULL                                                        THEN 'Recall Not Yet Due'
                ELSE 'No Recall Set'
            END AS Current_State,

            SYSUTCDATETIME(),
            SYSUTCDATETIME()

        FROM #appts a
        LEFT JOIN #first_attended  fa   ON fa.Tenant_ID  = a.Tenant_ID  AND fa.Patient_ID  = a.Patient_ID
        LEFT JOIN #referrals       ref  ON ref.Tenant_ID = a.Tenant_ID  AND ref.Patient_ID = a.Patient_ID
        LEFT JOIN Silver.Patients  pat  ON pat.Tenant_ID = a.Tenant_ID  AND pat.Patient_ID = a.Patient_ID
        LEFT JOIN #latest_recall   lr   ON lr.Tenant_ID  = a.Tenant_ID  AND lr.Patient_ID  = a.Patient_ID
        LEFT JOIN Silver.Appointment_Reason_Map arm_this
                       ON arm_this.Reason_Text = NULLIF(TRIM(a.Reason), '')

        -- Next completed appointment (any) to detect 'Seen Again' in Current_State.
        OUTER APPLY (
            SELECT TOP 1 sa.Appointment_ID
            FROM #appts sa
            WHERE sa.Tenant_ID   = a.Tenant_ID
              AND sa.Patient_ID  = a.Patient_ID
              AND sa.Completed_DT IS NOT NULL
              AND sa.Start_DT    > a.Start_DT
            ORDER BY sa.Start_DT, sa.Appointment_ID
        ) seen_again

        -- Next chronological appointment (completed or active, excludes cancelled/DNA) for Next_Appointment and Delay.
        OUTER APPLY (
            SELECT TOP 1 nx.Appointment_ID, nx.Reason, nx.Start_DT
            FROM #appts nx
            WHERE nx.Tenant_ID   = a.Tenant_ID
              AND nx.Patient_ID  = a.Patient_ID
              AND nx.Cancelled_DT IS NULL
              AND nx.DNA_DT      IS NULL
              AND nx.Start_DT    > a.Start_DT
            ORDER BY nx.Start_DT, nx.Appointment_ID
        ) nxt
        LEFT JOIN Silver.Appointment_Reason_Map arm_nxt
                       ON arm_nxt.Reason_Text = NULLIF(TRIM(nxt.Reason), '')

        -- Next active (uncompleted, non-cancelled) future appointment for Current_State BBYL/Treatment Booked.
        OUTER APPLY (
            SELECT TOP 1 ab.Appointment_ID, ab.Booked_Via_API
            FROM #appts ab
            WHERE ab.Tenant_ID   = a.Tenant_ID
              AND ab.Patient_ID  = a.Patient_ID
              AND ab.Cancelled_DT IS NULL
              AND ab.DNA_DT      IS NULL
              AND ab.Completed_DT IS NULL
              AND ab.Start_DT    > a.Start_DT
            ORDER BY ab.Start_DT, ab.Appointment_ID
        ) active_bkg

        -- Most recent prior completed appointment; used to detect BBYL (created on same date).
        OUTER APPLY (
            SELECT TOP 1 CAST(pa.Start_DT AS DATE) AS Prev_Date
            FROM #appts pa
            WHERE pa.Tenant_ID   = a.Tenant_ID
              AND pa.Patient_ID  = a.Patient_ID
              AND pa.Completed_DT IS NOT NULL
              AND pa.Start_DT    < a.Start_DT
            ORDER BY pa.Start_DT DESC, pa.Appointment_ID DESC
        ) prev_appt

        -- First appointment on or after the patient's earliest referral to identify 'Referral' channel.
        OUTER APPLY (
            SELECT TOP 1 ra.Appointment_ID
            FROM #appts ra
            WHERE ref.Earliest_Referral_DT IS NOT NULL
              AND ra.Tenant_ID  = a.Tenant_ID
              AND ra.Patient_ID = a.Patient_ID
              AND ra.Start_DT   >= ref.Earliest_Referral_DT
            ORDER BY ra.Start_DT, ra.Appointment_ID
        ) ref_appt;

        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE IF EXISTS #appts;
        DROP TABLE IF EXISTS #first_attended;
        DROP TABLE IF EXISTS #referrals;
        DROP TABLE IF EXISTS #latest_recall;

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
