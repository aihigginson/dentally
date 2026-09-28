--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Aggregate_Site_Patient_Current] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Site_Patient_Current
--  Author           :  AIH
--  Initial Date     :  07/05/2026
--  History          :
--    *01     07/05/2026  AIH  Initial Release
--  Notes:
--    Grain  : Site × Patient × Tenant  (one row per patient per site, current state)
--    Pattern: Full DELETE + INSERT each run.
--    pk      generated via ROW_NUMBER() — no IDENTITY column.
--    Retained_Patients : patient has had at least one appointment (Last_Appointment_Date IS NOT NULL)
--    Active_Patients   : Gold.Dim_Patients.Active = 1
--    Recall_Due        : patient has an overdue recall (Days_Overdue > 0 AND recall not completed)
--    Recall_Sent       : patient has had at least one recall notification issued
--                        (Workflow_Status IN ('Sent','Completed') — adjust if workflow labels differ)
--    Future_Appointment: patient has Next_Appointment_Date in the future
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Load_Aggregate_Site_Patient_Current
--               @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Aggregate_Site_Patient_Current]
GO
CREATE PROCEDURE [Gold].[usp_Load_Aggregate_Site_Patient_Current]
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

        DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);

        -- ── Recall status per patient ────────────────────────────────────────
        -- Aggregated from Fact_Recalls: overdue flag and sent flag.
        SELECT
            r.fk_Patient,
            r.Tenant_ID,
            MAX(CASE WHEN r.Days_Overdue > 0 AND r.Status <> 'Completed'
                     THEN 1 ELSE 0 END)                 AS Recall_Due,
            MAX(CASE WHEN r.Workflow_Status IN ('sent','completed','Sent','Completed')
                     THEN 1 ELSE 0 END)                 AS Recall_Sent
        INTO #recall_status
        FROM Gold.Fact_Recalls r
        GROUP BY r.fk_Patient, r.Tenant_ID;

        -- ── Patient × Site spine ─────────────────────────────────────────────
        -- Drive from Dim_Patients (Site_ID column links to Dim_Practice_Sites).
        -- Patients without a site assignment are still included with fk_Site = NULL.
        SELECT
            dps.pk_Practice_Site                        AS fk_Site,
            dp.pk_Patient                               AS fk_Patient,
            dp.Tenant_ID,
            CAST(CASE WHEN dp.Last_Appointment_Date IS NOT NULL
                      THEN 1 ELSE 0 END AS BIT)         AS Retained_Patients,
            CAST(ISNULL(dp.Active, 0) AS BIT)           AS Active_Patients,
            CAST(ISNULL(rc.Recall_Due,  0) AS BIT)      AS Recall_Due,
            CAST(ISNULL(rc.Recall_Sent, 0) AS BIT)      AS Recall_Sent,
            CAST(CASE WHEN dp.Next_Appointment_Date > @Today
                      THEN 1 ELSE 0 END AS BIT)         AS Future_Appointment,
            dp.First_Appointment_Date
        INTO #src
        FROM Gold.Dim_Patients dp
        LEFT JOIN Gold.Dim_Practice_Sites dps ON dps.Site_ID   = dp.Site_ID
                                              AND dps.Tenant_ID = dp.Tenant_ID
        LEFT JOIN #recall_status              rc  ON rc.fk_Patient = dp.pk_Patient
                                              AND rc.Tenant_ID  = dp.Tenant_ID
        WHERE dp.pk_Patient > 0;   -- exclude unknown (-1) seed row

        -- ── Full rebuild ─────────────────────────────────────────────────────
        DELETE FROM Gold.Aggregate_Site_Patient_Current;
        SET @My_Deletes = @@ROWCOUNT;

        -- Rolling 36 months of BOTH revenue types, plus attendance alongside it. Measured from
        -- today rather than from the last loaded date on purpose: a window that moved with the
        -- data would make every patient look less valuable after a day without a load.
        DECLARE @Value_Months SMALLINT = 36;
        DECLARE @Value_From   DATE = DATEADD(MONTH, -@Value_Months, @Today);

        DROP TABLE IF EXISTS #pv_rev;
        SELECT r.Tenant_ID, r.fk_Patient,
               SUM(CASE WHEN r.Revenue_Type = 'Capitation' THEN 0 ELSE r.Amount END) AS inv,
               SUM(CASE WHEN r.Revenue_Type = 'Capitation' THEN r.Amount ELSE 0 END) AS cap
        INTO   #pv_rev
        FROM   Gold.Fact_Revenue r
        JOIN   Gold.Dim_Date d ON d.pk_Date = r.fk_Date
        WHERE  r.fk_Patient > 0 AND d.Full_Date >= @Value_From AND d.Full_Date <= @Today
        GROUP BY r.Tenant_ID, r.fk_Patient;

        -- fk_Patient > 0 excludes the lunchtime blocking-out rows, which are not visits.
        DROP TABLE IF EXISTS #pv_att;
        SELECT a.Tenant_ID, a.fk_Patient, COUNT(*) AS attended,
               MAX(CAST(a.Start_Time AS DATE)) AS last_attended
        INTO   #pv_att
        FROM   Gold.Fact_Appointments a
        WHERE  a.fk_Patient > 0 AND a.Is_Completed = 1
          AND  CAST(a.Start_Time AS DATE) >= @Value_From
          AND  CAST(a.Start_Time AS DATE) <= @Today
        GROUP BY a.Tenant_ID, a.fk_Patient;

        INSERT INTO Gold.Aggregate_Site_Patient_Current (
            pk_Site_Patient_Current,
            fk_Site, fk_Patient, Tenant_ID,
            Retained_Patients, Active_Patients,
            Recall_Due, Recall_Sent, Future_Appointment,
            Value_Window_Months, Value_Window_From,
            Value_Invoiced, Value_Capitation, Value_Total,
            Appointments_Attended, Last_Attended_Date, Value_Per_Year,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY s.Tenant_ID, s.fk_Site, s.fk_Patient)
                                                        AS pk_Site_Patient_Current,
            s.fk_Site,
            s.fk_Patient,
            s.Tenant_ID,
            s.Retained_Patients,
            s.Active_Patients,
            s.Recall_Due,
            s.Recall_Sent,
            s.Future_Appointment,
            @Value_Months,
            @Value_From,
            CAST(ISNULL(r.inv, 0) AS DECIMAL(18,4)),
            CAST(ISNULL(r.cap, 0) AS DECIMAL(18,4)),
            CAST(ISNULL(r.inv, 0) + ISNULL(r.cap, 0) AS DECIMAL(18,4)),
            ISNULL(t.attended, 0),
            t.last_attended,
            -- Annualised over the time the patient has actually been on the books inside the
            -- window, so somebody who joined eight months ago is not made to look poor beside
            -- somebody who has been here the whole three years.
            CAST((ISNULL(r.inv, 0) + ISNULL(r.cap, 0)) * 12.0
                 / NULLIF(CASE WHEN s.First_Appointment_Date > @Value_From
                               THEN DATEDIFF(MONTH, s.First_Appointment_Date, @Today)
                               ELSE @Value_Months END, 0) AS DECIMAL(18,4)),
            SYSUTCDATETIME(),
            SYSUTCDATETIME()
        FROM #src s
        LEFT JOIN #pv_rev r ON r.Tenant_ID = s.Tenant_ID AND r.fk_Patient = s.fk_Patient
        LEFT JOIN #pv_att t ON t.Tenant_ID = s.Tenant_ID AND t.fk_Patient = s.fk_Patient;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
        DROP TABLE #recall_status;
        DROP TABLE #pv_rev;
        DROP TABLE #pv_att;

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
