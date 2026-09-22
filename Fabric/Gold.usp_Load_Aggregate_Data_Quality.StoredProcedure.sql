--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Aggregate_Data_Quality] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Data_Quality
--  Author           :  AIH
--  Initial Date     :  22/09/2026
--  History          :
--    *01     22/09/2026  AIH  Initial Release (V172)
--  Notes:
--    Grain  : Tenant x Check  (one row per check per practice, passing checks included)
--    Pattern: Full DELETE + INSERT each run. pk via ROW_NUMBER() -- no IDENTITY.
--
--    Every check in Config.Data_Quality_Check needs a counting branch in #hits below,
--    matched on Check_Code. A catalogue row with no branch reports 0 for ever, which on
--    the report is indistinguishable from a clean practice. The final SELECT is built
--    catalogue-first (tenants CROSS JOIN catalogue LEFT JOIN #hits) precisely so that a
--    check with nothing to report still produces a visible 0 row.
--
--    Populations are the denominator for Pct_Affected, keyed by Population_Key on the
--    catalogue. They are computed per tenant regardless of whether any check fires.
--
--    Windows: DIARY_NOT_CLOSED / DIARY_LEFT_OPEN look back @Recent_Days only. Unbounded,
--    the first is tens of thousands of rows of history that no practice will ever work
--    through; 90 days is the span where setting the real outcome is still plausible.
--
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Load_Aggregate_Data_Quality
--               @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Aggregate_Data_Quality]
GO
CREATE PROCEDURE [Gold].[usp_Load_Aggregate_Data_Quality]
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

        DECLARE @Today          DATE = CAST(SYSUTCDATETIME() AS DATE);
        DECLARE @Recent_Days    INT  = 90;
        DECLARE @Dormant_Months INT  = 24;

        -- ── Tenant spine ─────────────────────────────────────────────────────
        -- A practice with no patients is not a live practice; there is nothing to
        -- score. Driving from Dim_Patients keeps part-populated test tenants out.
        SELECT DISTINCT Tenant_ID
        INTO #tenants
        FROM Gold.Dim_Patients
        WHERE pk_Patient > 0;

        -- ── Appointments with a real calendar date ───────────────────────────
        -- ==> A DIARY BLOCK IS NOT AN APPOINTMENT. <== Lunch, admin time and held slots are
        -- stored in Fact_Appointments exactly like bookings, but carry NO PATIENT
        -- (fk_Patient is the -1 unknown sentinel). Every diary check below therefore tests
        -- Is_Patient_Appointment, and so do the two diary denominators.
        --
        -- This is not a hypothetical tidy-up. Without it, on tenant 100:
        --   * "booked with a clinician who has left" reported 305, every one of them a 13:00
        --     Lunch block against two departed dentists -- the true answer is 0
        --   * "never closed off" reported 373, of which 355 were blocks that can never be
        --     closed because there is nobody to close them for -- the true answer is 18
        -- Both would have been the loudest numbers on the scorecard, and both were noise.
        SELECT a.Tenant_ID,
               a.fk_Patient,
               a.fk_Practitioner,
               a.State,
               ISNULL(a.Is_Cancelled, 0)   AS Is_Cancelled,
               d.Full_Date                 AS Appt_Date,
               CAST(CASE WHEN a.fk_Patient > 0 THEN 1 ELSE 0 END AS BIT)
                                           AS Is_Patient_Appointment
        INTO #appt
        FROM Gold.Fact_Appointments a
        JOIN Gold.Dim_Date d ON d.pk_Date = a.fk_Date_Start;

        -- ── Denominators ─────────────────────────────────────────────────────
        SELECT t.Tenant_ID,
               ACTIVE_PATIENTS = (SELECT COUNT(*) FROM Gold.Dim_Patients p
                                  WHERE p.Tenant_ID = t.Tenant_ID AND p.pk_Patient > 0
                                    AND p.Active = 1),
               FUTURE_APPOINTMENTS = (SELECT COUNT(*) FROM #appt a
                                  WHERE a.Tenant_ID = t.Tenant_ID
                                    AND a.Appt_Date > @Today AND a.Is_Cancelled = 0
                                    AND a.Is_Patient_Appointment = 1),
               RECENT_APPOINTMENTS = (SELECT COUNT(*) FROM #appt a
                                  WHERE a.Tenant_ID = t.Tenant_ID
                                    AND a.Appt_Date <  @Today
                                    AND a.Appt_Date >= DATEADD(DAY, -@Recent_Days, @Today)
                                    AND a.Is_Patient_Appointment = 1),
               OVERDUE_RECALLS = (SELECT COUNT(*) FROM Gold.Fact_Recalls r
                                  WHERE r.Tenant_ID = t.Tenant_ID
                                    AND r.Days_Overdue > 0 AND ISNULL(r.Is_In_Scope, 0) = 1),
               ACTIVE_PRACTITIONERS = (SELECT COUNT(*) FROM Gold.Dim_Practitioners pr
                                  WHERE pr.Tenant_ID = t.Tenant_ID AND pr.pk_Practitioner > 0
                                    AND pr.Active = 1),
               TREATMENTS = (SELECT COUNT(*) FROM Gold.Dim_Treatments tr
                                  WHERE tr.Tenant_ID = t.Tenant_ID AND tr.pk_Treatment > 0)
        INTO #pop
        FROM #tenants t;

        -- ── The checks ───────────────────────────────────────────────────────
        -- One branch per Check_Code in Config.Data_Quality_Check. Counts only --
        -- the wording, severity and guidance all come from the catalogue.
        SELECT Check_Code, Tenant_ID, Records_Affected
        INTO #hits
        FROM (
            -- Diary
            SELECT 'DIARY_LEAVER_BOOKED' AS Check_Code, a.Tenant_ID, COUNT(*) AS Records_Affected
            FROM #appt a
            JOIN Gold.Dim_Practitioners pr ON pr.pk_Practitioner = a.fk_Practitioner
                                          AND pr.Tenant_ID       = a.Tenant_ID
            WHERE a.Appt_Date > @Today AND a.Is_Cancelled = 0
              AND a.Is_Patient_Appointment = 1 AND pr.Active = 0
            GROUP BY a.Tenant_ID

            UNION ALL
            SELECT 'DIARY_INACTIVE_PATIENT', a.Tenant_ID, COUNT(*)
            FROM #appt a
            JOIN Gold.Dim_Patients p ON p.pk_Patient = a.fk_Patient
                                    AND p.Tenant_ID  = a.Tenant_ID
            WHERE a.Appt_Date > @Today AND a.Is_Cancelled = 0
              AND a.Is_Patient_Appointment = 1
              AND p.pk_Patient > 0 AND p.Active = 0
            GROUP BY a.Tenant_ID

            UNION ALL
            SELECT 'DIARY_NOT_CLOSED', a.Tenant_ID, COUNT(*)
            FROM #appt a
            WHERE a.Appt_Date <  @Today
              AND a.Appt_Date >= DATEADD(DAY, -@Recent_Days, @Today)
              AND a.Is_Patient_Appointment = 1
              AND a.State IN ('Pending', 'Confirmed')
            GROUP BY a.Tenant_ID

            UNION ALL
            SELECT 'DIARY_LEFT_OPEN', a.Tenant_ID, COUNT(*)
            FROM #appt a
            WHERE a.Appt_Date <  @Today
              AND a.Appt_Date >= DATEADD(DAY, -@Recent_Days, @Today)
              AND a.Is_Patient_Appointment = 1
              AND a.State IN ('Arrived', 'In surgery')
            GROUP BY a.Tenant_ID

            -- Patients
            UNION ALL
            SELECT 'PAT_NO_CONTACT', p.Tenant_ID, COUNT(*)
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Is_Email_Missing = 1 AND p.Is_Phone_Missing = 1
            GROUP BY p.Tenant_ID

            UNION ALL
            SELECT 'PAT_NO_RECALL_DATE', p.Tenant_ID, COUNT(*)
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Dentist_Recall_Date IS NULL AND p.Hygienist_Recall_Date IS NULL
            GROUP BY p.Tenant_ID

            UNION ALL
            SELECT 'PAT_DORMANT', p.Tenant_ID, COUNT(*)
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Last_Appointment_Date < DATEADD(MONTH, -@Dormant_Months, @Today)
              AND (p.Next_Appointment_Date IS NULL OR p.Next_Appointment_Date <= @Today)
            GROUP BY p.Tenant_ID

            UNION ALL
            SELECT 'PAT_NO_DENTIST', p.Tenant_ID, COUNT(*)
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Dentist_Practitioner_ID IS NULL
            GROUP BY p.Tenant_ID

            UNION ALL
            SELECT 'PAT_NEVER_SEEN', p.Tenant_ID, COUNT(*)
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Last_Appointment_Date IS NULL
              AND (p.Next_Appointment_Date IS NULL OR p.Next_Appointment_Date <= @Today)
            GROUP BY p.Tenant_ID

            UNION ALL
            SELECT 'PAT_NO_DOB', p.Tenant_ID, COUNT(*)
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Date_Of_Birth IS NULL
            GROUP BY p.Tenant_ID

            UNION ALL
            SELECT 'PAT_NO_MARKETING_PREF', p.Tenant_ID, COUNT(*)
            FROM Gold.Dim_Patients p
            WHERE p.pk_Patient > 0 AND p.Active = 1
              AND p.Marketing_Consent IS NULL
            GROUP BY p.Tenant_ID

            -- Recalls
            UNION ALL
            SELECT 'RECALL_NO_REMINDER', r.Tenant_ID, COUNT(*)
            FROM Gold.Fact_Recalls r
            WHERE r.Days_Overdue > 0
              AND ISNULL(r.Is_In_Scope, 0) = 1
              AND ISNULL(r.Is_Reminder_Sent, 0) = 0
            GROUP BY r.Tenant_ID

            -- People
            UNION ALL
            SELECT 'PRAC_NO_GDC', pr.Tenant_ID, COUNT(*)
            FROM Gold.Dim_Practitioners pr
            WHERE pr.pk_Practitioner > 0 AND pr.Active = 1
              AND (pr.GDC_Number IS NULL OR LTRIM(RTRIM(pr.GDC_Number)) = '')
            GROUP BY pr.Tenant_ID

            -- Treatments
            UNION ALL
            SELECT 'TRT_NO_CODE', tr.Tenant_ID, COUNT(*)
            FROM Gold.Dim_Treatments tr
            WHERE tr.pk_Treatment > 0
              AND (tr.Treatment_Code IS NULL OR LTRIM(RTRIM(tr.Treatment_Code)) = '')
            GROUP BY tr.Tenant_ID

            UNION ALL
            SELECT 'TRT_NO_CATEGORY', tr.Tenant_ID, COUNT(*)
            FROM Gold.Dim_Treatments tr
            WHERE tr.pk_Treatment > 0
              AND (tr.Treatment_Category_Name IS NULL
                   OR LTRIM(RTRIM(tr.Treatment_Category_Name)) = '')
            GROUP BY tr.Tenant_ID
        ) x;

        -- ── Full rebuild ─────────────────────────────────────────────────────
        DELETE FROM Gold.Aggregate_Data_Quality;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Aggregate_Data_Quality (
            pk_Data_Quality, Tenant_ID, Check_Code, Check_Category, Check_Name,
            Severity, Severity_Sort, Why_It_Matters, What_To_Do,
            Records_Affected, Population, Pct_Affected, Has_Issue, Display_Order,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY s.Tenant_ID, s.Display_Order, s.Check_Code),
            s.Tenant_ID, s.Check_Code, s.Check_Category, s.Check_Name,
            s.Severity, s.Severity_Sort, s.Why_It_Matters, s.What_To_Do,
            s.Records_Affected,
            s.Population,
            CASE WHEN s.Population > 0
                 THEN CAST(ROUND(100.0 * s.Records_Affected / s.Population, 2) AS DECIMAL(5,2))
            END,
            CAST(CASE WHEN s.Records_Affected > 0 THEN 1 ELSE 0 END AS BIT),
            s.Display_Order,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM (
            SELECT t.Tenant_ID,
                   c.Check_Code, c.Check_Category, c.Check_Name,
                   c.Severity, c.Severity_Sort, c.Why_It_Matters, c.What_To_Do,
                   c.Display_Order,
                   ISNULL(h.Records_Affected, 0) AS Records_Affected,
                   CASE c.Population_Key
                        WHEN 'ACTIVE_PATIENTS'      THEN pp.ACTIVE_PATIENTS
                        WHEN 'FUTURE_APPOINTMENTS'  THEN pp.FUTURE_APPOINTMENTS
                        WHEN 'RECENT_APPOINTMENTS'  THEN pp.RECENT_APPOINTMENTS
                        WHEN 'OVERDUE_RECALLS'      THEN pp.OVERDUE_RECALLS
                        WHEN 'ACTIVE_PRACTITIONERS' THEN pp.ACTIVE_PRACTITIONERS
                        WHEN 'TREATMENTS'           THEN pp.TREATMENTS
                   END AS Population
            FROM #tenants t
            CROSS JOIN Config.Data_Quality_Check c
            JOIN #pop pp ON pp.Tenant_ID = t.Tenant_ID
            LEFT JOIN #hits h ON h.Tenant_ID  = t.Tenant_ID
                             AND h.Check_Code = c.Check_Code
            WHERE c.Is_Active = 1
        ) s;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #hits;
        DROP TABLE #pop;
        DROP TABLE #appt;
        DROP TABLE #tenants;

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
