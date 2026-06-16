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

        -- Source set: every appointment that can be ordered in time. Anchors
        -- include all states (the flags travel through so the view/visual can
        -- exclude cancelled/DNA if wanted); pointer TARGETS are restricted to
        -- non-cancelled, non-DNA appointments (a real future visit).
        DROP TABLE IF EXISTS #appts;
        SELECT
            Tenant_ID, bk_Appointment_ID, fk_Patient, fk_Practitioner,
            fk_Practice_Site, fk_Date_Start, Start_Time,
            Booking, Appointment_Reason,
            ISNULL(Is_Cancelled, 0) AS Is_Cancelled,
            ISNULL(Is_DNA, 0)       AS Is_DNA,
            ISNULL(Is_Completed, 0) AS Is_Completed
        INTO #appts
        FROM Gold.Fact_Appointments
        WHERE Start_Time IS NOT NULL;

        -- Full rebuild.
        DELETE FROM Gold.Fact_Appointment_Journey;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Fact_Appointment_Journey
        (
            Tenant_ID, bk_Appointment_ID, fk_Patient, fk_Practitioner,
            fk_Practice_Site, fk_Date_Start, Start_Time, Booking, Appointment_Reason,
            Is_Cancelled, Is_DNA, Is_Completed,
            fk_Appointment_Next, fk_Appointment_Exam, fk_Appointment_Hygiene,
            fk_Appointment_Not_Hygiene, DW_Created_At, DW_Updated_At
        )
        SELECT
            a.Tenant_ID, a.bk_Appointment_ID, a.fk_Patient, a.fk_Practitioner,
            a.fk_Practice_Site, a.fk_Date_Start, a.Start_Time, a.Booking, a.Appointment_Reason,
            a.Is_Cancelled, a.Is_DNA, a.Is_Completed,
            nxt.bk_Appointment_ID, ex.bk_Appointment_ID, hy.bk_Appointment_ID, nh.bk_Appointment_ID,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #appts a
        OUTER APPLY (
            SELECT TOP 1 b.bk_Appointment_ID
            FROM #appts b
            WHERE b.Tenant_ID = a.Tenant_ID AND b.fk_Patient = a.fk_Patient
              AND b.Start_Time > a.Start_Time AND b.Is_Cancelled = 0 AND b.Is_DNA = 0
            ORDER BY b.Start_Time, b.bk_Appointment_ID
        ) nxt
        OUTER APPLY (
            SELECT TOP 1 b.bk_Appointment_ID
            FROM #appts b
            WHERE b.Tenant_ID = a.Tenant_ID AND b.fk_Patient = a.fk_Patient
              AND b.Start_Time > a.Start_Time AND b.Is_Cancelled = 0 AND b.Is_DNA = 0
              AND b.Appointment_Reason = 'Exam'
            ORDER BY b.Start_Time, b.bk_Appointment_ID
        ) ex
        OUTER APPLY (
            SELECT TOP 1 b.bk_Appointment_ID
            FROM #appts b
            WHERE b.Tenant_ID = a.Tenant_ID AND b.fk_Patient = a.fk_Patient
              AND b.Start_Time > a.Start_Time AND b.Is_Cancelled = 0 AND b.Is_DNA = 0
              AND b.Appointment_Reason = 'Hygiene'
            ORDER BY b.Start_Time, b.bk_Appointment_ID
        ) hy
        OUTER APPLY (
            SELECT TOP 1 b.bk_Appointment_ID
            FROM #appts b
            WHERE b.Tenant_ID = a.Tenant_ID AND b.fk_Patient = a.fk_Patient
              AND b.Start_Time > a.Start_Time AND b.Is_Cancelled = 0 AND b.Is_DNA = 0
              AND b.Appointment_Reason <> 'Hygiene'
            ORDER BY b.Start_Time, b.bk_Appointment_ID
        ) nh;

        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE IF EXISTS #appts;

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
