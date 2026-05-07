--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Site_Patient_Practitioner_Daily
--  Author           :  AIH
--  Initial Date     :  07/05/2026
--  History          :
--    *01     07/05/2026  AIH  Initial Release
--  Notes:
--    Grain  : Site × Patient × Practitioner × Date × Tenant
--    Pattern: Full DELETE + INSERT each run (no incremental merge).
--    pk      generated via ROW_NUMBER() — no IDENTITY column.
--    NHS_UDAs / NHS_UOAs are NULL pending a claim-level Silver source;
--    update the stub CTE when Silver.Nhs_Claims schema is confirmed.
--    BBYL (Book Before You Leave) is approximated as: appointment was
--    completed AND the patient had a new appointment created (booked)
--    on the same calendar day for a future date.
--    Worked_Hours is the practitioner's total clinical availability for
--    the day (from Fact_Practitioner_Diaries); it is the same value
--    across every patient row for that practitioner on that day.
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Load_Aggregate_Site_Patient_Practitioner_Daily
--               @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Aggregate_Site_Patient_Practitioner_Daily]
GO
CREATE PROCEDURE [Gold].[usp_Load_Aggregate_Site_Patient_Practitioner_Daily]
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

        -- ── Appointment spine ────────────────────────────────────────────────
        -- One row per (Site, Patient, Practitioner, Date, Tenant).
        -- Cancelled appointments are excluded from counts but DNA are included.
        SELECT
            apt.fk_Practice_Site                                                AS fk_Site,
            apt.fk_Patient,
            apt.fk_Practitioner,
            apt.fk_Date_Start                                                   AS fk_Date,
            apt.Tenant_ID,
            dd.Full_Date                                                        AS Apt_Date,

            COUNT(*)                                                            AS Appointments,
            SUM(CAST(apt.Is_DNA AS INT))                                        AS DNA_Appointments,

            -- BBYL: completed appointment where the patient booked a future visit on the same day
            SUM(CASE
                    WHEN apt.Is_Completed = 1
                     AND EXISTS (
                            SELECT 1
                            FROM   Gold.Fact_Appointments next_apt
                            WHERE  next_apt.fk_Patient    = apt.fk_Patient
                            AND    next_apt.Tenant_ID     = apt.Tenant_ID
                            AND    next_apt.fk_Date_Created = apt.fk_Date_Start
                            AND    next_apt.fk_Date_Start > apt.fk_Date_Start
                     )
                    THEN 1 ELSE 0
                END)                                                            AS BBYL_Appointments,

            -- Exams: appointments whose Reason contains 'Exam' (case-insensitive)
            SUM(CASE WHEN apt.Reason LIKE '%Exam%' THEN 1 ELSE 0 END)          AS Exam_Count,

            -- Appointment_Hours: scheduled clinical time in hours
            CAST(SUM(ISNULL(apt.Duration_Mins, 0)) AS DECIMAL(10,2)) / 60.0   AS Appointment_Hours,

            -- New_Patient: first appointment ever for this patient falls on this date
            MAX(CASE WHEN dp.First_Appointment_Date = dd.Full_Date THEN 1 ELSE 0 END)
                                                                                AS New_Patient,

            -- Future_Appointment: patient currently has a next appointment in the diary
            MAX(CASE WHEN dp.Next_Appointment_Date > dd.Full_Date THEN 1 ELSE 0 END)
                                                                                AS Future_Appointment

        INTO #apt_agg
        FROM  Gold.Fact_Appointments   apt
        LEFT JOIN Gold.Dim_Patients    dp  ON dp.pk_Patient = apt.fk_Patient
        LEFT JOIN Gold.Dim_Date        dd  ON dd.pk_Date    = apt.fk_Date_Start
        WHERE apt.Is_Cancelled = 0
        GROUP BY
            apt.fk_Practice_Site,
            apt.fk_Patient,
            apt.fk_Practitioner,
            apt.fk_Date_Start,
            apt.Tenant_ID,
            dd.Full_Date;

        -- ── Revenue (invoice date matched to appointment date) ────────────────
        SELECT
            ii.fk_Practice_Site                         AS fk_Site,
            ii.fk_Patient,
            ii.fk_Practitioner,
            ii.fk_Date_Invoice                          AS fk_Date,
            ii.Tenant_ID,
            SUM(ii.Invoice_NHS_Amount)                  AS NHS_Revenue,
            SUM(ii.Invoice_Amount - ii.Invoice_NHS_Amount) AS Private_Revenue
        INTO #rev_agg
        FROM Gold.Fact_Invoice_Items ii
        GROUP BY
            ii.fk_Practice_Site,
            ii.fk_Patient,
            ii.fk_Practitioner,
            ii.fk_Date_Invoice,
            ii.Tenant_ID;

        -- ── Treatment plan items ─────────────────────────────────────────────
        -- Treatment_Count : completed items on this date
        -- Open_Treatment_Plan : open (not completed, not charged) items on or before this date
        SELECT
            tpi.fk_Practice_Site,
            tpi.fk_Patient,
            tpi.fk_Practitioner,
            tpi.fk_Date_Created                         AS fk_Date,
            tpi.Tenant_ID,
            SUM(CAST(tpi.Completed AS INT))             AS Treatment_Count,
            SUM(CASE WHEN tpi.Completed = 0 AND tpi.Charged = 0 THEN 1 ELSE 0 END)
                                                        AS Open_Treatment_Plan
        INTO #tpi_agg
        FROM Gold.Fact_Treatment_Plan_Items tpi
        GROUP BY
            tpi.fk_Practice_Site,
            tpi.fk_Patient,
            tpi.fk_Practitioner,
            tpi.fk_Date_Created,
            tpi.Tenant_ID;

        -- ── Practitioner diary hours ─────────────────────────────────────────
        -- Available_Clinical_Mins is the scheduled clinical time after breaks.
        -- This is per practitioner per day (same value across all patient rows that day).
        SELECT
            fpd.fk_Practitioner,
            fpd.fk_Date_Day                             AS fk_Date,
            fpd.Tenant_ID,
            CAST(SUM(fpd.Available_Clinical_Mins) AS DECIMAL(10,2)) / 60.0
                                                        AS Worked_Hours
        INTO #diary_agg
        FROM Gold.Fact_Practitioner_Diaries fpd
        GROUP BY
            fpd.fk_Practitioner,
            fpd.fk_Date_Day,
            fpd.Tenant_ID;

        -- ── Full rebuild ─────────────────────────────────────────────────────
        DELETE FROM Gold.Aggregate_Site_Patient_Practitioner_Daily;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Aggregate_Site_Patient_Practitioner_Daily (
            pk_Site_Patient_Practitioner_Daily,
            fk_Site, fk_Patient, fk_Practitioner, fk_Date, Tenant_ID,
            NHS_UDAs, NHS_UOAs,
            Appointments, DNA_Appointments, BBYL_Appointments,
            NHS_Revenue, Private_Revenue,
            Open_Treatment_Plan, Future_Appointment,
            Exam_Count, Treatment_Count, New_Patient,
            Worked_Hours, Appointment_Hours,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY a.Tenant_ID, a.fk_Date, a.fk_Site, a.fk_Practitioner, a.fk_Patient)
                                                        AS pk_Site_Patient_Practitioner_Daily,
            a.fk_Site,
            a.fk_Patient,
            a.fk_Practitioner,
            a.fk_Date,
            a.Tenant_ID,
            NULL                                        AS NHS_UDAs,       -- pending Silver.Nhs_Claims
            NULL                                        AS NHS_UOAs,       -- pending Silver.Nhs_Claims
            a.Appointments,
            a.DNA_Appointments,
            a.BBYL_Appointments,
            ISNULL(r.NHS_Revenue,     0)                AS NHS_Revenue,
            ISNULL(r.Private_Revenue, 0)                AS Private_Revenue,
            ISNULL(t.Open_Treatment_Plan, 0)            AS Open_Treatment_Plan,
            CAST(a.Future_Appointment AS BIT)           AS Future_Appointment,
            a.Exam_Count,
            ISNULL(t.Treatment_Count, 0)                AS Treatment_Count,
            CAST(a.New_Patient AS BIT)                  AS New_Patient,
            d.Worked_Hours,
            a.Appointment_Hours,
            SYSUTCDATETIME(),
            SYSUTCDATETIME()
        FROM #apt_agg a
        LEFT JOIN #rev_agg   r ON r.fk_Site        = a.fk_Site
                               AND r.fk_Patient     = a.fk_Patient
                               AND r.fk_Practitioner= a.fk_Practitioner
                               AND r.fk_Date        = a.fk_Date
                               AND r.Tenant_ID      = a.Tenant_ID
        LEFT JOIN #tpi_agg   t ON t.fk_Practice_Site = a.fk_Site
                               AND t.fk_Patient       = a.fk_Patient
                               AND t.fk_Practitioner  = a.fk_Practitioner
                               AND t.fk_Date          = a.fk_Date
                               AND t.Tenant_ID        = a.Tenant_ID
        LEFT JOIN #diary_agg d ON d.fk_Practitioner = a.fk_Practitioner
                               AND d.fk_Date         = a.fk_Date
                               AND d.Tenant_ID       = a.Tenant_ID;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #apt_agg;
        DROP TABLE #rev_agg;
        DROP TABLE #tpi_agg;
        DROP TABLE #diary_agg;

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
