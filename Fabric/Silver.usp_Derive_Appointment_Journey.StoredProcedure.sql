--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Derive_Appointment_Journey
--  Author           :  AIH
--  Initital Date    :  13/05/2026
--  History          :
--    *01     13/05/2026  AIH Initial Release
--    *02     13/05/2026  AIH Fix datetime casting (strip tz suffix); Next_Visit defaults;
--                            Emergency next visit treated as Exam; Recall Sent via First_Reminder_Sent_At
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Silver.usp_Derive_Appointment_Journey @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Derive_Appointment_Journey]    Script Date: 13/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Derive_Appointment_Journey]
GO
CREATE PROCEDURE [Silver].[usp_Derive_Appointment_Journey]
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
        DELETE FROM [Silver].[Appointment_Journey_Attrs];
        SET @My_Deletes = @@ROWCOUNT;

        WITH appts AS (
            -- Cast varchar date columns once for reuse throughout.
            -- LEFT(..., 23) strips any timezone suffix (e.g. +00:00) before casting to datetime2(3).
            SELECT
                a.Tenant_ID,
                a.Appointment_Id,
                a.Patient_Id,
                a.Reason,
                a.Booked_Via_Api,
                TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time),        ''), 23) AS datetime2(3)) AS Start_DT,
                TRY_CAST(LEFT(NULLIF(TRIM(a.Completed_At),      ''), 23) AS datetime2(3)) AS Completed_DT,
                TRY_CAST(LEFT(NULLIF(TRIM(a.Cancelled_At),      ''), 23) AS datetime2(3)) AS Cancelled_DT,
                TRY_CAST(LEFT(NULLIF(TRIM(a.Did_Not_Attend_At), ''), 23) AS datetime2(3)) AS DNA_DT
            FROM Silver.Appointments a
            WHERE a.Appointment_Id IS NOT NULL
        ),
        first_attended AS (
            -- Lowest Appointment_Id among attended appointments per patient; used to flag 'New' channel
            SELECT Tenant_ID, Patient_Id, MIN(Appointment_Id) AS First_Appt_Id
            FROM appts
            WHERE Completed_DT IS NOT NULL
            GROUP BY Tenant_ID, Patient_Id
        ),
        referrals AS (
            -- Earliest referral DW load date per patient; DW_Created_At is the only available
            -- proxy for referral creation date (no API-supplied Created_At on Patient_Referrals)
            SELECT Tenant_ID, Patient_Id, MIN(DW_Created_At) AS Earliest_Referral_DT
            FROM Silver.Patient_Referrals
            GROUP BY Tenant_ID, Patient_Id
        ),
        recall_ranked AS (
            SELECT
                Tenant_ID, Patient_Id, Due_Date, First_Reminder_Sent_At,
                ROW_NUMBER() OVER (
                    PARTITION BY Tenant_ID, Patient_Id
                    ORDER BY Due_Date DESC, DW_Created_At DESC
                ) AS rn
            FROM Silver.Recalls
        ),
        latest_recall AS (
            SELECT Tenant_ID, Patient_Id, Due_Date, First_Reminder_Sent_At
            FROM recall_ranked
            WHERE rn = 1
        )
        INSERT INTO [Silver].[Appointment_Journey_Attrs] (
            [Tenant_ID], [Appointment_Id],
            [Booking], [This_Visit], [Next_Visit], [Future_Appointment],
            [DW_Created_At], [DW_Updated_At]
        )
        SELECT
            a.Tenant_ID,
            a.Appointment_Id,

            -- Booking: how the patient booked into the practice (priority order)
            CASE
                WHEN ref_appt.Appointment_Id = a.Appointment_Id THEN 'Referral'
                WHEN fa.First_Appt_Id        = a.Appointment_Id THEN 'New'
                WHEN a.Booked_Via_Api        = 1                THEN 'BBYL'
                ELSE 'Reception'
            END AS Booking,

            -- This_Visit: mapped category if known, otherwise raw reason text, otherwise NULL
            COALESCE(arm_this.Category, NULLIF(TRIM(a.Reason), '')) AS This_Visit,

            -- Next_Visit: planned category of the patient's next booked appointment.
            -- Emergency bookings are unplanned so treated as if no appointment (defaults to Exam).
            -- Active patients with no next booking are expected to return for an Exam.
            CASE
                WHEN nxt.Appointment_Id IS NULL AND pat.Active = 0                           THEN 'Closed'
                WHEN nxt.Appointment_Id IS NULL                                               THEN 'Exam'
                WHEN COALESCE(arm_nxt.Category, NULLIF(TRIM(nxt.Reason), '')) = 'Emergency' THEN 'Exam'
                ELSE COALESCE(arm_nxt.Category, NULLIF(TRIM(nxt.Reason), ''))
            END AS Next_Visit,

            -- Future_Appointment: patient's post-visit status (all appointments)
            CASE
                WHEN seen_again.Appointment_Id IS NOT NULL                       THEN 'Seen Again'
                WHEN nxt.Appointment_Id IS NOT NULL AND nxt.Booked_Via_Api = 1  THEN 'BBYL'
                WHEN nxt.Appointment_Id IS NOT NULL                              THEN 'Other Booked'
                WHEN pat.Active = 0                                              THEN 'Will Not See Again'
                WHEN lr.First_Reminder_Sent_At IS NOT NULL                       THEN 'Recall Sent'
                WHEN lr.Due_Date < CAST(SYSDATETIME() AS DATE)                  THEN 'Recall Overdue'
                WHEN lr.Due_Date IS NOT NULL                                     THEN 'Recall Not Yet Due'
                ELSE 'No Recall Set'
            END AS Future_Appointment,

            SYSUTCDATETIME(),
            SYSUTCDATETIME()

        FROM appts a
        LEFT JOIN first_attended  fa   ON fa.Tenant_ID  = a.Tenant_ID  AND fa.Patient_Id  = a.Patient_Id
        LEFT JOIN referrals       ref  ON ref.Tenant_ID = a.Tenant_ID  AND ref.Patient_Id = a.Patient_Id
        LEFT JOIN Silver.Patients pat  ON pat.Tenant_ID = a.Tenant_ID  AND pat.Patient_Id = a.Patient_Id
        LEFT JOIN latest_recall   lr   ON lr.Tenant_ID  = a.Tenant_ID  AND lr.Patient_Id  = a.Patient_Id
        LEFT JOIN Silver.Appointment_Reason_Map arm_this
               ON arm_this.Reason_Text = NULLIF(TRIM(a.Reason), '')

        -- Next completed appointment (any) to detect 'Seen Again'
        OUTER APPLY (
            SELECT TOP 1 sa.Appointment_Id
            FROM appts sa
            WHERE sa.Tenant_ID   = a.Tenant_ID
              AND sa.Patient_Id  = a.Patient_Id
              AND sa.Completed_DT IS NOT NULL
              AND sa.Start_DT    > a.Start_DT
            ORDER BY sa.Start_DT, sa.Appointment_Id
        ) seen_again

        -- Next appointment still in an active booking state (not cancelled, DNA'd, or completed)
        OUTER APPLY (
            SELECT TOP 1 nx.Appointment_Id, nx.Booked_Via_Api, nx.Reason
            FROM appts nx
            WHERE nx.Tenant_ID   = a.Tenant_ID
              AND nx.Patient_Id  = a.Patient_Id
              AND nx.Cancelled_DT IS NULL
              AND nx.DNA_DT      IS NULL
              AND nx.Completed_DT IS NULL
              AND nx.Start_DT    > a.Start_DT
            ORDER BY nx.Start_DT, nx.Appointment_Id
        ) nxt
        LEFT JOIN Silver.Appointment_Reason_Map arm_nxt
               ON arm_nxt.Reason_Text = NULLIF(TRIM(nxt.Reason), '')

        -- First appointment on or after the patient's earliest referral to identify 'Referral' channel
        OUTER APPLY (
            SELECT TOP 1 ra.Appointment_Id
            FROM appts ra
            WHERE ref.Earliest_Referral_DT IS NOT NULL
              AND ra.Tenant_ID  = a.Tenant_ID
              AND ra.Patient_Id = a.Patient_Id
              AND ra.Start_DT   >= ref.Earliest_Referral_DT
            ORDER BY ra.Start_DT, ra.Appointment_Id
        ) ref_appt;

        SET @My_Inserts = @@ROWCOUNT;

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
