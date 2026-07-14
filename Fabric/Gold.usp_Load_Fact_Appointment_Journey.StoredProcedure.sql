--DECLARE @i BIGINT=0,@u BIGINT=0,@d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Appointment_Journey] @Mode='PROD',@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Appointment_Journey
--  Author           :  AIH
--  Initital Date    :  16/06/2026
--  History          :
--    *01     16/06/2026  AIH Initial Release -- appointment-grain journey base
--                            table with 4 next-appointment pointers (any / Exam /
--                            Hygiene / Not-Hygiene). FULL REBUILD: a cancellation
--                            shifts earlier appointments' "next" pointer, so a
--                            forward delta would miss them. Sourced from
--                            Gold.Fact_Appointments (Booking + Appointment_Reason
--                            already derived there). Resolved into per-mode
--                            Delay/Next/Current State by Gold.vw_Fact_Appointment_Journey.
--    *02     10/07/2026  AIH Replace the 4x correlated OUTER APPLY TOP-1 next-pointers with a
--                            single windowed pass (FIRST_VALUE ... IGNORE NULLS + a LAST_VALUE
--                            tie broadcast to keep the strict "Start_Time >" semantics). The
--                            OUTER APPLYs re-scanned each patient's appts 4x (O(n^2)) on a
--                            columnstore work table that can't be indexed -> ~13 min on ~173k
--                            rows. Windowed = one sort. Verified 0-diff on 246,520 dev rows; ~2s.
--  To Run			 :   DECLARE @Run_Inserts BIGINT,@Run_Updates BIGINT,@Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_Appointment_Journey @Run_Inserts=@Run_Inserts OUT,@Run_Updates=@Run_Updates OUT,@Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Appointment_Journey]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Appointment_Journey]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       SMALLINT         = 1
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

        -- Full rebuild. A cancellation shifts an earlier appointment's "next" pointer,
        -- so a forward delta would miss it -- the whole grain is rebuilt each run.
        DELETE FROM Gold.Fact_Appointment_Journey;
        SET @My_Deletes = @@ROWCOUNT;

        -- Next-appointment pointers (any / Exam / Hygiene / Not-Hygiene) in ONE windowed
        -- pass instead of 4 correlated OUTER APPLY TOP-1 lookups. Anchors keep every state
        -- (the flags travel through so the view/visual can still exclude cancelled/DNA);
        -- pointer TARGETS are the non-cancelled, non-DNA appointments (a real future visit).
        -- FIRST_VALUE(...) IGNORE NULLS over the following rows finds the next valid target.
        -- The old code used a strict "b.Start_Time > a.Start_Time", so appointments sharing a
        -- Start_Time were NOT each other's "next"; the LAST_VALUE broadcast over each
        -- (patient, Start_Time) group reproduces that exactly (only the group's last row, by
        -- bk_Appointment_ID, has its "1 FOLLOWING" strictly later). Verified 0-diff vs the
        -- OUTER APPLY output on 246,520 dev rows; ~2s vs ~13 min (the APPLYs were O(n^2) on a
        -- columnstore work table Fabric can't index).
        ;WITH src AS (
            SELECT
                Tenant_ID, bk_Appointment_ID, fk_Patient, fk_Practitioner, fk_Practice_Site,
                fk_Date_Start, Start_Time, Booking, Appointment_Reason,
                ISNULL(Is_Cancelled, 0) AS Is_Cancelled,
                ISNULL(Is_DNA, 0)       AS Is_DNA,
                ISNULL(Is_Completed, 0) AS Is_Completed,
                CASE WHEN ISNULL(Is_Cancelled, 0) = 0 AND ISNULL(Is_DNA, 0) = 0 THEN 1 ELSE 0 END AS Is_Valid_Target
            FROM Gold.Fact_Appointments
            WHERE Start_Time IS NOT NULL
        ),
        cand AS (
            SELECT
                Tenant_ID, bk_Appointment_ID, fk_Patient, fk_Practitioner, fk_Practice_Site,
                fk_Date_Start, Start_Time, Booking, Appointment_Reason, Is_Cancelled, Is_DNA, Is_Completed,
                FIRST_VALUE(CASE WHEN Is_Valid_Target = 1
                                 THEN bk_Appointment_ID END) IGNORE NULLS
                    OVER (PARTITION BY Tenant_ID, fk_Patient ORDER BY Start_Time, bk_Appointment_ID
                          ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING) AS c_next,
                FIRST_VALUE(CASE WHEN Is_Valid_Target = 1 AND Appointment_Reason = 'Exam'
                                 THEN bk_Appointment_ID END) IGNORE NULLS
                    OVER (PARTITION BY Tenant_ID, fk_Patient ORDER BY Start_Time, bk_Appointment_ID
                          ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING) AS c_exam,
                FIRST_VALUE(CASE WHEN Is_Valid_Target = 1 AND Appointment_Reason = 'Hygiene'
                                 THEN bk_Appointment_ID END) IGNORE NULLS
                    OVER (PARTITION BY Tenant_ID, fk_Patient ORDER BY Start_Time, bk_Appointment_ID
                          ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING) AS c_hygiene,
                FIRST_VALUE(CASE WHEN Is_Valid_Target = 1 AND Appointment_Reason <> 'Hygiene'
                                 THEN bk_Appointment_ID END) IGNORE NULLS
                    OVER (PARTITION BY Tenant_ID, fk_Patient ORDER BY Start_Time, bk_Appointment_ID
                          ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING) AS c_not_hygiene
            FROM src
        ),
        newj AS (
            SELECT
                Tenant_ID, bk_Appointment_ID, fk_Patient, fk_Practitioner, fk_Practice_Site,
                fk_Date_Start, Start_Time, Booking, Appointment_Reason, Is_Cancelled, Is_DNA, Is_Completed,
                LAST_VALUE(c_next)        OVER (PARTITION BY Tenant_ID, fk_Patient, Start_Time ORDER BY bk_Appointment_ID
                                               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS fk_Appointment_Next,
                LAST_VALUE(c_exam)        OVER (PARTITION BY Tenant_ID, fk_Patient, Start_Time ORDER BY bk_Appointment_ID
                                               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS fk_Appointment_Exam,
                LAST_VALUE(c_hygiene)     OVER (PARTITION BY Tenant_ID, fk_Patient, Start_Time ORDER BY bk_Appointment_ID
                                               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS fk_Appointment_Hygiene,
                LAST_VALUE(c_not_hygiene) OVER (PARTITION BY Tenant_ID, fk_Patient, Start_Time ORDER BY bk_Appointment_ID
                                               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS fk_Appointment_Not_Hygiene
            FROM cand
        )
        INSERT INTO Gold.Fact_Appointment_Journey
        (
            Tenant_ID, bk_Appointment_ID, fk_Patient, fk_Practitioner,
            fk_Practice_Site, fk_Date_Start, Start_Time, Booking, Appointment_Reason,
            Is_Cancelled, Is_DNA, Is_Completed,
            fk_Appointment_Next, fk_Appointment_Exam, fk_Appointment_Hygiene,
            fk_Appointment_Not_Hygiene, DW_Created_At, DW_Updated_At
        )
        SELECT
            Tenant_ID, bk_Appointment_ID, fk_Patient, fk_Practitioner,
            fk_Practice_Site, fk_Date_Start, Start_Time, Booking, Appointment_Reason,
            Is_Cancelled, Is_DNA, Is_Completed,
            fk_Appointment_Next, fk_Appointment_Exam, fk_Appointment_Hygiene,
            fk_Appointment_Not_Hygiene, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM newj;

        SET @My_Inserts = @@ROWCOUNT;

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************
        SET @Run_Inserts = @My_Inserts;
        SET @Run_Updates = @My_Updates;
        SET @Run_Deletes = @My_Deletes;
    END TRY
    BEGIN CATCH
        SET @Run_Inserts = @My_Inserts;
        SET @Run_Updates = @My_Updates;
        SET @Run_Deletes = @My_Deletes;
        ;THROW;
    END CATCH
END
GO
