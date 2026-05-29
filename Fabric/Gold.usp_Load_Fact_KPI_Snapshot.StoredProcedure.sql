--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_KPI_Snapshot] @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_KPI_Snapshot
--  Author           :  AIH
--  Initial Date     :  18/05/2026
--  History          :
--    *01     18/05/2026  AIH  Initial Release — open_courses_value
--    *02     19/05/2026  AIH  Remove #items temp table; cross-join directly on Fact_Treatment_Plan_Items
--                             (Fabric rejects CROSS JOIN between two temp tables); cast #charged bk to VARCHAR(50)
--    *03     19/05/2026  AIH  Replace Site_ID VARCHAR with fk_Practice_Site (pk from Dim_Practice_Sites);
--                             replace Snapshot_Date DATE with fk_Date INT (days since 1999-12-31)
--    *04     19/05/2026  AIH  Add retention_outlook metric — current-state only (recalls deleted on attendance);
--                             preserved across full reload by excluding from DELETE; accumulates weekly
--    *05     25/05/2026  AIH  Add open_courses (A1) and outstanding_invoices (A2) historical snapshots;
--                             add active_patients, lapsed_patients, overdue_recalls (A3) accumulating
--                             snapshots; update DELETE exclusion list for all accumulating metrics
--    *06     29/05/2026  AIH  Fix outstanding_invoices: use Invoice_Amount_Outstanding not Invoice_Amount
--                             (face value was being summed instead of unpaid balance)
--    *08     29/05/2026  AIH  Add WTD/MTD rows: always include today in both grains so the current
--                             week and current month always have a snapshot record
--    *09     29/05/2026  AIH  Retention_Outlook: remove #has_next_appt / #recall_scope temp tables;
--                             use pre-computed Fact_Recalls columns (Retention_Outlook_In_Scope,
--                             Retention_Outlook_Booked) populated by usp_Load_Fact_Recalls
--    *07     29/05/2026  AIH  Add average_plan_value (A3) and treatment_acceptance_rate (A4) as historical
--                             reconstructions from Dim_Treatment_Plans; convert active_patients (A5) and
--                             lapsed_patients (A6) from accumulating to historical using Dim_Patients date
--                             fields (lapsed = Last_Appointment_Date < D-730d, active = new minus lapsed)
--
--  Purpose:
--    Populates Gold.Fact_KPI_Snapshot with point-in-time metric values
--    at two grains:
--      'weekly'  — every Friday from (today - 3 years) to today
--      'monthly' — last calendar day of each month in the same range
--
--    Grain: Tenant x Site x Practitioner x Metric x fk_Date x Grain.
--    Site and practice totals are aggregations of practitioner rows in DAX.
--
--    Two extra rows are always added so the current period is never missing:
--      'weekly'  today — WTD row; omitted if today is already a Friday
--      'monthly' today — MTD row; omitted if today is already month-end
--
--    open_courses_value (historical)
--    ================================
--    An item is "in pipeline" at snapshot date D when ALL of:
--      1. Item created on or before D       (fk_Date_Created <= D)
--      2. Parent plan started on or before D (Start_Date <= D)
--      3. Parent plan not yet ended/completed at D
--      4. Item not yet invoiced at D
--    Items with NULL or zero Price are excluded.
--
--    open_courses (historical, A1)
--    ================================
--    A plan is open at snapshot date D when:
--      Start_Date IS NOT NULL AND Start_Date <= D
--      AND (End_Date IS NULL OR End_Date > D)
--      AND (Completed_Date IS NULL OR Completed_Date > D)
--    Grouped by Tenant x Site (fk_Practitioner = -1, Supports_Practitioner = 0).
--
--    outstanding_invoices (historical, A2)
--    ================================
--    An invoice is outstanding at D when:
--      Invoice_Date <= D AND (Paid_Date IS NULL OR Paid_Date > D)
--    Aggregated to invoice level (Invoice_Amount) to avoid double-counting items.
--    Grouped by Tenant x Site (fk_Practitioner = -1, Supports_Practitioner = 0).
--
--    average_plan_value (historical, A3)
--    ================================
--    Average Private_Treatment_Value of plans open at D (same open-plan
--    gate as open_courses).  NULL Private_Treatment_Value treated as 0.
--
--    treatment_acceptance_rate (historical, A4)
--    ================================
--    Cumulative acceptance rate at D: plans with Start_Date <= D divided
--    by all plans with Created_Date <= D.  Returns a ratio (0.0-1.0).
--
--    lapsed_patients (historical, A5)
--    ================================
--    Patients with First_Appointment_Date <= D whose Last_Appointment_Date
--    is more than 730 days before D.  Grouped by Tenant x Site.
--
--    active_patients (historical, A6)
--    ================================
--    Patients with First_Appointment_Date <= D minus lapsed patients at D.
--    Computed in a single CROSS JOIN pass using conditional SUMs.
--    Grouped by Tenant x Site.
--
--    overdue_recalls, retention_outlook (accumulating)
--    ================================
--    Cannot be reconstructed historically (recalls deleted on attendance;
--    no patient-status history in Gold).  One row per (Tenant, Site)
--    appended at today's date each run, guarded by IF NOT EXISTS.
--    Excluded from the full DELETE so trend history accumulates.
--
--  To Run:
--    DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
--    EXEC Gold.usp_Load_Fact_KPI_Snapshot
--         @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_KPI_Snapshot]    Script Date: 18/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_KPI_Snapshot]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_KPI_Snapshot]
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

        DECLARE @Today      DATE = CAST(SYSUTCDATETIME() AS DATE);
        DECLARE @Snap_Start DATE = DATEADD(YEAR, -3, @Today);
        DECLARE @acc_fk_date INT  = DATEDIFF(d, '19991231', @Today);

        -- ── Snapshot date spine ──────────────────────────────────────────────
        -- Fridays (weekly) + month-end days (monthly), from 3 years ago to today.
        -- When a Friday falls on a month-end, two rows appear (different grain).
        SELECT
            d.Full_Date                                        AS Snapshot_Date,
            CAST('weekly' AS VARCHAR(10))                      AS Snapshot_Grain
        INTO #snap_dates
        FROM [Gold].[Dim_Date] d
        WHERE d.Full_Date BETWEEN @Snap_Start AND @Today
          AND DATENAME(WEEKDAY, d.Full_Date) = 'Friday'

        UNION ALL

        SELECT
            d.Full_Date,
            CAST('monthly' AS VARCHAR(10))
        FROM [Gold].[Dim_Date] d
        WHERE d.Full_Date BETWEEN @Snap_Start AND @Today
          AND d.Full_Date = EOMONTH(d.Full_Date)

        UNION ALL

        -- WTD: today as a weekly snapshot when today is not itself a Friday
        SELECT @Today, CAST('weekly' AS VARCHAR(10))
        FROM (SELECT 1 AS n) AS t
        WHERE DATENAME(WEEKDAY, @Today) <> 'Friday'

        UNION ALL

        -- MTD: today as a monthly snapshot when today is not already month-end
        SELECT @Today, CAST('monthly' AS VARCHAR(10))
        FROM (SELECT 1 AS n) AS t
        WHERE @Today <> CAST(EOMONTH(@Today) AS DATE);

        -- ── First invoice date per treatment plan item ───────────────────────
        -- Determines when an item exited the pipeline (was charged).
        -- Cast to VARCHAR(50) so the join to bk_Treatment_Plan_Item_ID (UUID) is type-safe.
        SELECT
            CAST(fii.[Treatment_Plan_Item_ID] AS VARCHAR(50))  AS bk_Treatment_Plan_Item_ID,
            fii.[Tenant_ID],
            MIN(dd.Full_Date)                                  AS First_Invoice_Date
        INTO #charged
        FROM [Gold].[Fact_Invoice_Items] fii
        INNER JOIN [Gold].[Dim_Date] dd
            ON dd.pk_Date = fii.[fk_Date_Invoice]
        WHERE fii.[Treatment_Plan_Item_ID] IS NOT NULL
        GROUP BY fii.[Treatment_Plan_Item_ID], fii.[Tenant_ID];

        -- ── A0: open_courses_value — pipeline snapshot ───────────────────────
        -- Cross-join directly against Fact_Treatment_Plan_Items rather than a
        -- #items temp table — Fabric rejects CROSS JOIN between two temp tables.
        SELECT
            DATEDIFF(d, '19991231', sd.Snapshot_Date)          AS fk_Date,
            sd.Snapshot_Grain,
            tpi.[Tenant_ID],
            ISNULL(dps.[pk_Practice_Site], -1)                 AS fk_Practice_Site,
            tpi.[fk_Practitioner],
            CAST('open_courses_value' AS VARCHAR(100))         AS Metric,
            SUM(tpi.[Price])                                   AS Value
        INTO #results
        FROM #snap_dates sd
        CROSS JOIN [Gold].[Fact_Treatment_Plan_Items] tpi
        INNER JOIN [Gold].[Dim_Date] dc
            ON dc.pk_Date = tpi.[fk_Date_Created]
        INNER JOIN [Gold].[Dim_Treatment_Plans] dtp
            ON dtp.[pk_Treatment_Plan] = tpi.[fk_Treatment_Plan]
           AND dtp.[Tenant_ID]         = tpi.[Tenant_ID]
        LEFT JOIN [Gold].[Dim_Practitioners] dp
            ON dp.[pk_Practitioner] = tpi.[fk_Practitioner]
           AND dp.[Tenant_ID]       = tpi.[Tenant_ID]
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps
            ON dps.[Site_ID]   = dp.[Site_ID]
           AND dps.[Tenant_ID] = tpi.[Tenant_ID]
        LEFT JOIN #charged c
            ON c.[bk_Treatment_Plan_Item_ID] = tpi.[bk_Treatment_Plan_Item_ID]
           AND c.[Tenant_ID]                 = tpi.[Tenant_ID]
        WHERE
            tpi.[Price]      IS NOT NULL
          AND tpi.[Price]     > 0
          AND dtp.[Start_Date] IS NOT NULL
            -- Item existed at snapshot date
          AND dc.[Full_Date]                                   <= sd.Snapshot_Date
            -- Plan started at or before snapshot date
          AND dtp.[Start_Date]                                 <= sd.Snapshot_Date
            -- Plan not yet ended at snapshot date
          AND (dtp.[End_Date]        IS NULL OR dtp.[End_Date]                       > sd.Snapshot_Date)
            -- Plan not yet completed at snapshot date
          AND (dtp.[Completed_Date]  IS NULL OR CAST(dtp.[Completed_Date] AS DATE)  > sd.Snapshot_Date)
            -- Item not yet invoiced at snapshot date
          AND (c.[First_Invoice_Date] IS NULL OR c.[First_Invoice_Date]             > sd.Snapshot_Date)
        GROUP BY
            sd.Snapshot_Date,
            sd.Snapshot_Grain,
            tpi.[Tenant_ID],
            dps.[pk_Practice_Site],
            tpi.[fk_Practitioner];

        -- ── A1: open_courses — count of open treatment plans ─────────────────
        -- A plan is open at D when started <= D, not yet ended, not yet completed.
        -- Grouped by Tenant x Site only (Supports_Practitioner = 0).
        -- Site derived via Practitioner_ID → Dim_Practitioners → Dim_Practice_Sites.
        INSERT INTO #results (fk_Date, Snapshot_Grain, Tenant_ID, fk_Practice_Site, fk_Practitioner, Metric, Value)
        SELECT
            DATEDIFF(d, '19991231', sd.Snapshot_Date)          AS fk_Date,
            sd.Snapshot_Grain,
            dtp.[Tenant_ID],
            ISNULL(dps.[pk_Practice_Site], -1)                 AS fk_Practice_Site,
            -1                                                  AS fk_Practitioner,
            CAST('open_courses' AS VARCHAR(100))               AS Metric,
            CAST(COUNT(*) AS DECIMAL(18,4))                    AS Value
        FROM #snap_dates sd
        CROSS JOIN [Gold].[Dim_Treatment_Plans] dtp
        LEFT JOIN [Gold].[Dim_Practitioners] dp
            ON dp.[Practitioner_ID] = dtp.[Practitioner_ID]
           AND dp.[Tenant_ID]       = dtp.[Tenant_ID]
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps
            ON dps.[Site_ID]   = dp.[Site_ID]
           AND dps.[Tenant_ID] = dtp.[Tenant_ID]
        WHERE dtp.[Start_Date] IS NOT NULL
          AND dtp.[Start_Date]                                  <= sd.Snapshot_Date
          AND (dtp.[End_Date]       IS NULL OR dtp.[End_Date]                      > sd.Snapshot_Date)
          AND (dtp.[Completed_Date] IS NULL OR CAST(dtp.[Completed_Date] AS DATE) > sd.Snapshot_Date)
        GROUP BY
            sd.Snapshot_Date,
            sd.Snapshot_Grain,
            dtp.[Tenant_ID],
            dps.[pk_Practice_Site];

        -- ── A2: outstanding_invoices — unpaid invoice totals ─────────────────
        -- An invoice is outstanding at D when issued <= D and not paid by D.
        -- Aggregated at invoice level (Invoice_Amount) to avoid double-counting items.
        -- CTE avoids a second temp table (Fabric rejects CROSS JOIN temp-to-temp).
        -- Grouped by Tenant x Site only (Supports_Practitioner = 0).
        ;WITH inv_agg AS (
            SELECT
                fii.[Invoice_ID],
                fii.[Tenant_ID],
                ISNULL(fii.[fk_Practice_Site], -1)             AS fk_Practice_Site,
                MAX(fii.[Invoice_Amount_Outstanding])           AS Invoice_Outstanding,
                MIN(dd_i.[Full_Date])                          AS Invoice_Date,
                MAX(dd_p.[Full_Date])                          AS Paid_Date
            FROM [Gold].[Fact_Invoice_Items] fii
            INNER JOIN [Gold].[Dim_Date] dd_i ON dd_i.pk_Date = fii.[fk_Date_Invoice]
            LEFT  JOIN [Gold].[Dim_Date] dd_p ON dd_p.pk_Date = fii.[fk_Date_Paid]
            WHERE fii.[Invoice_Amount] > 0
            GROUP BY fii.[Invoice_ID], fii.[Tenant_ID], fii.[fk_Practice_Site]
        )
        INSERT INTO #results (fk_Date, Snapshot_Grain, Tenant_ID, fk_Practice_Site, fk_Practitioner, Metric, Value)
        SELECT
            DATEDIFF(d, '19991231', sd.Snapshot_Date)          AS fk_Date,
            sd.Snapshot_Grain,
            inv.[Tenant_ID],
            inv.[fk_Practice_Site],
            -1                                                  AS fk_Practitioner,
            CAST('outstanding_invoices' AS VARCHAR(100))       AS Metric,
            SUM(inv.[Invoice_Outstanding])                     AS Value
        FROM #snap_dates sd
        CROSS JOIN inv_agg inv
        WHERE inv.[Invoice_Date] <= sd.Snapshot_Date
          AND (inv.[Paid_Date] IS NULL OR inv.[Paid_Date] > sd.Snapshot_Date)
        GROUP BY
            sd.Snapshot_Date,
            sd.Snapshot_Grain,
            inv.[Tenant_ID],
            inv.[fk_Practice_Site];

        -- ── A3: average_plan_value — mean private value of open plans ────────
        -- Same open-plan gate as A1 (open_courses).
        -- Grouped by Tenant x Site only (Supports_Practitioner = 0).
        INSERT INTO #results (fk_Date, Snapshot_Grain, Tenant_ID, fk_Practice_Site, fk_Practitioner, Metric, Value)
        SELECT
            DATEDIFF(d, '19991231', sd.Snapshot_Date)          AS fk_Date,
            sd.Snapshot_Grain,
            dtp.[Tenant_ID],
            ISNULL(dps.[pk_Practice_Site], -1)                 AS fk_Practice_Site,
            -1                                                  AS fk_Practitioner,
            CAST('average_plan_value' AS VARCHAR(100))         AS Metric,
            SUM(ISNULL(dtp.[Private_Treatment_Value], 0))
                / NULLIF(CAST(COUNT(*) AS DECIMAL(18,4)), 0)   AS Value
        FROM #snap_dates sd
        CROSS JOIN [Gold].[Dim_Treatment_Plans] dtp
        LEFT JOIN [Gold].[Dim_Practitioners] dp
            ON dp.[Practitioner_ID] = dtp.[Practitioner_ID]
           AND dp.[Tenant_ID]       = dtp.[Tenant_ID]
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps
            ON dps.[Site_ID]   = dp.[Site_ID]
           AND dps.[Tenant_ID] = dtp.[Tenant_ID]
        WHERE dtp.[Start_Date] IS NOT NULL
          AND dtp.[Start_Date]                                  <= sd.Snapshot_Date
          AND (dtp.[End_Date]       IS NULL OR dtp.[End_Date]                      > sd.Snapshot_Date)
          AND (dtp.[Completed_Date] IS NULL OR CAST(dtp.[Completed_Date] AS DATE) > sd.Snapshot_Date)
        GROUP BY
            sd.Snapshot_Date,
            sd.Snapshot_Grain,
            dtp.[Tenant_ID],
            dps.[pk_Practice_Site];

        -- ── A4: treatment_acceptance_rate — cumulative acceptance ratio ───────
        -- Denominator: all plans Created_Date <= D.
        -- Numerator: of those, plans with Start_Date IS NOT NULL AND Start_Date <= D.
        -- Grouped by Tenant x Site only (Supports_Practitioner = 0).
        INSERT INTO #results (fk_Date, Snapshot_Grain, Tenant_ID, fk_Practice_Site, fk_Practitioner, Metric, Value)
        SELECT
            DATEDIFF(d, '19991231', sd.Snapshot_Date)          AS fk_Date,
            sd.Snapshot_Grain,
            dtp.[Tenant_ID],
            ISNULL(dps.[pk_Practice_Site], -1)                 AS fk_Practice_Site,
            -1                                                  AS fk_Practitioner,
            CAST('treatment_acceptance_rate' AS VARCHAR(100))  AS Metric,
            CAST(SUM(CASE WHEN dtp.[Start_Date] IS NOT NULL
                           AND dtp.[Start_Date] <= sd.Snapshot_Date THEN 1 ELSE 0 END) AS DECIMAL(18,4))
                / NULLIF(CAST(COUNT(*) AS DECIMAL(18,4)), 0)   AS Value
        FROM #snap_dates sd
        CROSS JOIN [Gold].[Dim_Treatment_Plans] dtp
        LEFT JOIN [Gold].[Dim_Practitioners] dp
            ON dp.[Practitioner_ID] = dtp.[Practitioner_ID]
           AND dp.[Tenant_ID]       = dtp.[Tenant_ID]
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps
            ON dps.[Site_ID]   = dp.[Site_ID]
           AND dps.[Tenant_ID] = dtp.[Tenant_ID]
        WHERE dtp.[Created_Date] IS NOT NULL
          AND CAST(dtp.[Created_Date] AS DATE) <= sd.Snapshot_Date
        GROUP BY
            sd.Snapshot_Date,
            sd.Snapshot_Grain,
            dtp.[Tenant_ID],
            dps.[pk_Practice_Site];

        -- ── A5: lapsed_patients — historical from Dim_Patients ────────────────
        -- Lapsed at D: First_Appointment_Date <= D AND Last_Appointment_Date < D-730d.
        -- Grouped by Tenant x Site only (Supports_Practitioner = 0).
        INSERT INTO #results (fk_Date, Snapshot_Grain, Tenant_ID, fk_Practice_Site, fk_Practitioner, Metric, Value)
        SELECT
            DATEDIFF(d, '19991231', sd.Snapshot_Date)          AS fk_Date,
            sd.Snapshot_Grain,
            dp.[Tenant_ID],
            ISNULL(dps.[pk_Practice_Site], -1)                 AS fk_Practice_Site,
            -1                                                  AS fk_Practitioner,
            CAST('lapsed_patients' AS VARCHAR(100))            AS Metric,
            CAST(COUNT(*) AS DECIMAL(18,4))                    AS Value
        FROM #snap_dates sd
        CROSS JOIN [Gold].[Dim_Patients] dp
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps
            ON dps.[Site_ID]   = dp.[Site_ID]
           AND dps.[Tenant_ID] = dp.[Tenant_ID]
        WHERE dp.[First_Appointment_Date] IS NOT NULL
          AND dp.[First_Appointment_Date]                       <= sd.Snapshot_Date
          AND dp.[Last_Appointment_Date] IS NOT NULL
          AND dp.[Last_Appointment_Date]                        < DATEADD(DAY, -730, sd.Snapshot_Date)
        GROUP BY
            sd.Snapshot_Date,
            sd.Snapshot_Grain,
            dp.[Tenant_ID],
            dps.[pk_Practice_Site];

        -- ── A6: active_patients — historical from Dim_Patients ───────────────
        -- Active at D = new cumulative (First_Appt <= D) minus lapsed at D.
        -- Single CROSS JOIN pass with conditional SUMs avoids a second temp table.
        -- Grouped by Tenant x Site only (Supports_Practitioner = 0).
        INSERT INTO #results (fk_Date, Snapshot_Grain, Tenant_ID, fk_Practice_Site, fk_Practitioner, Metric, Value)
        SELECT
            DATEDIFF(d, '19991231', sd.Snapshot_Date)          AS fk_Date,
            sd.Snapshot_Grain,
            dp.[Tenant_ID],
            ISNULL(dps.[pk_Practice_Site], -1)                 AS fk_Practice_Site,
            -1                                                  AS fk_Practitioner,
            CAST('active_patients' AS VARCHAR(100))            AS Metric,
            CAST(
                SUM(CASE WHEN dp.[First_Appointment_Date] <= sd.Snapshot_Date
                         THEN 1 ELSE 0 END)
              - SUM(CASE WHEN dp.[First_Appointment_Date] <= sd.Snapshot_Date
                          AND dp.[Last_Appointment_Date] IS NOT NULL
                          AND dp.[Last_Appointment_Date] < DATEADD(DAY, -730, sd.Snapshot_Date)
                         THEN 1 ELSE 0 END)
            AS DECIMAL(18,4))                                   AS Value
        FROM #snap_dates sd
        CROSS JOIN [Gold].[Dim_Patients] dp
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps
            ON dps.[Site_ID]   = dp.[Site_ID]
           AND dps.[Tenant_ID] = dp.[Tenant_ID]
        WHERE dp.[First_Appointment_Date] IS NOT NULL
        GROUP BY
            sd.Snapshot_Date,
            sd.Snapshot_Grain,
            dp.[Tenant_ID],
            dps.[pk_Practice_Site];

        -- ── Full reload (historical metrics only) ────────────────────────────
        -- Accumulating metrics are excluded: they cannot be reconstructed historically
        -- and their trend history must survive across full reloads.
        DELETE FROM [Gold].[Fact_KPI_Snapshot]
        WHERE [Metric] NOT IN ('retention_outlook', 'overdue_recalls');
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO [Gold].[Fact_KPI_Snapshot] (
            Tenant_ID, fk_Practice_Site, fk_Practitioner,
            Metric, fk_Date, Snapshot_Grain,
            Value, DW_Created_At
        )
        SELECT
            r.Tenant_ID,
            r.fk_Practice_Site,
            r.fk_Practitioner,
            r.Metric,
            r.fk_Date,
            r.Snapshot_Grain,
            r.Value,
            SYSUTCDATETIME()
        FROM #results r;

        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #snap_dates;
        DROP TABLE #charged;
        DROP TABLE #results;

        -- ── A7: Accumulating current-state snapshots ─────────────────────────
        -- These metrics cannot be reconstructed historically from Gold tables.
        -- Each run appends one row per (Tenant, Site) at today's date.

        -- overdue_recalls: in-scope recalls with no booking (matches DAX Overdue Recalls measure).
        -- Uses pre-computed Is_In_Scope and Is_Booked flags from Gold.Fact_Recalls.
        IF NOT EXISTS (
            SELECT 1 FROM [Gold].[Fact_KPI_Snapshot]
            WHERE [Metric] = 'overdue_recalls' AND [fk_Date] = @acc_fk_date
        )
        BEGIN
            INSERT INTO [Gold].[Fact_KPI_Snapshot] (
                Tenant_ID, fk_Practice_Site, fk_Practitioner,
                Metric, fk_Date, Snapshot_Grain,
                Value, DW_Created_At
            )
            SELECT
                fr.[Tenant_ID],
                ISNULL(dps.[pk_Practice_Site], -1)             AS fk_Practice_Site,
                -1                                              AS fk_Practitioner,
                'overdue_recalls'                              AS Metric,
                @acc_fk_date                                   AS fk_Date,
                'weekly'                                       AS Snapshot_Grain,
                CAST(COUNT(*) AS DECIMAL(18,4))                AS Value,
                SYSUTCDATETIME()
            FROM [Gold].[Fact_Recalls] fr
            LEFT JOIN [Gold].[Dim_Patients] dp
                ON dp.[pk_Patient]  = fr.[fk_Patient]
               AND dp.[Tenant_ID]   = fr.[Tenant_ID]
            LEFT JOIN [Gold].[Dim_Practice_Sites] dps
                ON dps.[Site_ID]   = dp.[Site_ID]
               AND dps.[Tenant_ID] = dp.[Tenant_ID]
            WHERE fr.[Is_In_Scope] = 1
              AND fr.[Is_Booked]   = 0
              AND fr.[fk_Patient]  IS NOT NULL
            GROUP BY fr.[Tenant_ID], dps.[pk_Practice_Site];

            SET @My_Inserts = @My_Inserts + @@ROWCOUNT;
        END

        -- ── Retention Outlook snapshot (current state, accumulates) ─────────
        -- Source: Fact_Recalls.Retention_Outlook_In_Scope / Retention_Outlook_Booked,
        -- pre-computed by usp_Load_Fact_Recalls. Collapsed to one row per patient
        -- via MAX before site-level aggregation so multi-recall patients count once.
        -- Historical reconstruction impossible (recalls deleted on attendance).
        -- Guard: skip if today's row already exists (idempotent on re-runs).
        IF NOT EXISTS (
            SELECT 1 FROM [Gold].[Fact_KPI_Snapshot]
            WHERE [Metric] = 'retention_outlook' AND [fk_Date] = @acc_fk_date
        )
        BEGIN
            INSERT INTO [Gold].[Fact_KPI_Snapshot] (
                Tenant_ID, fk_Practice_Site, fk_Practitioner,
                Metric, fk_Date, Snapshot_Grain,
                Value, DW_Created_At
            )
            SELECT
                rs.Tenant_ID,
                ISNULL(dps.pk_Practice_Site, -1)                              AS fk_Practice_Site,
                -1                                                             AS fk_Practitioner,
                'retention_outlook'                                            AS Metric,
                @acc_fk_date                                                   AS fk_Date,
                'weekly'                                                       AS Snapshot_Grain,
                CAST(SUM(rs.Booked) AS DECIMAL(18,4))
                    / NULLIF(CAST(SUM(rs.In_Scope) AS DECIMAL(18,4)), 0)      AS Value,
                SYSUTCDATETIME()
            FROM (
                -- Collapse multiple recalls per patient to a single in-scope / booked flag
                SELECT
                    fr.Tenant_ID,
                    fr.fk_Patient,
                    MAX(fr.Retention_Outlook_In_Scope)  AS In_Scope,
                    MAX(fr.Retention_Outlook_Booked)    AS Booked
                FROM [Gold].[Fact_Recalls] fr
                WHERE fr.fk_Patient IS NOT NULL
                  AND fr.Retention_Outlook_In_Scope = 1
                GROUP BY fr.Tenant_ID, fr.fk_Patient
            ) rs
            LEFT JOIN Gold.Dim_Patients       dp  ON  dp.pk_Patient  = rs.fk_Patient
                                                  AND dp.Tenant_ID   = rs.Tenant_ID
            LEFT JOIN Gold.Dim_Practice_Sites dps ON  dps.Site_ID    = dp.Site_ID
                                                  AND dps.Tenant_ID  = dp.Tenant_ID
            GROUP BY rs.Tenant_ID, dps.pk_Practice_Site;

            SET @My_Inserts = @My_Inserts + @@ROWCOUNT;
        END

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;

END
GO
