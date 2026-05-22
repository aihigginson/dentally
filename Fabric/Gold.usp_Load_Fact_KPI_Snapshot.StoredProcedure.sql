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
--    open_courses_value
--    ========================
--    An item is "in pipeline" at snapshot date D when ALL of:
--      1. Item created on or before D       (fk_Date_Created <= D)
--      2. Parent plan started on or before D (Start_Date <= D)
--      3. Parent plan not yet ended/completed at D
--             (End_Date IS NULL OR End_Date > D)
--             (Completed_Date IS NULL OR Completed_Date > D)
--      4. Item not yet invoiced at D — no Invoice_Item row with
--             Treatment_Plan_Item_ID match and fk_Date_Invoice <= D
--    Items with NULL or zero Price are excluded.
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
          AND d.Full_Date = EOMONTH(d.Full_Date);

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

        -- ── Pipeline snapshot per (snapshot, practitioner, tenant) ───────────
        -- Cross-join directly against Fact_Treatment_Plan_Items rather than a
        -- #items temp table — Fabric rejects CROSS JOIN between two temp tables.
        SELECT
            DATEDIFF(d, '19991231', sd.Snapshot_Date)          AS fk_Date,
            sd.Snapshot_Grain,
            tpi.[Tenant_ID],
            ISNULL(dps.[pk_Practice_Site], -1)                 AS fk_Practice_Site,
            tpi.[fk_Practitioner],
            CAST('open_courses_value' AS VARCHAR(100))   AS Metric,
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

        -- ── Full reload (open_courses_value only) ───────────────────────────
        -- retention_outlook is excluded: it is current-state only and accumulates
        -- across runs — deleting it would destroy the trend history.
        DELETE FROM [Gold].[Fact_KPI_Snapshot] WHERE [Metric] <> 'retention_outlook';
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

        -- ── Retention Outlook snapshot (current state, accumulates) ─────────
        -- Source: Fact_Recalls, which only contains open recall cycles.
        -- Recalls are deleted from Dentally when the patient attends, so
        -- historical reconstruction is impossible — each run captures today.
        -- Guard: skip if today's row already exists (idempotent on re-runs).
        DECLARE @ro_date    DATE = CAST(SYSUTCDATETIME() AS DATE);
        DECLARE @ro_fk_date INT  = DATEDIFF(d, '19991231', @ro_date);
        DECLARE @ro_back    DATE = DATEADD(MONTH, -24, @ro_date);
        DECLARE @ro_ahead   DATE = DATEADD(MONTH,   1, @ro_date);

        -- Patients who currently have any future non-cancelled appointment
        SELECT dp.pk_Patient, dp.Tenant_ID
        INTO #has_next_appt
        FROM Gold.Dim_Patients dp
        WHERE dp.Next_Appointment_Date IS NOT NULL;

        -- In-scope recalls: first reminder sent OR due within [24 months back, 1 month ahead]
        -- One row per patient (MAX collapses multiple recalls per patient)
        SELECT
            fr.Tenant_ID,
            fr.fk_Patient,
            MAX(CASE WHEN fr.Appointment_ID IS NOT NULL
                       OR na.pk_Patient IS NOT NULL THEN 1 ELSE 0 END) AS Has_Booking
        INTO #recall_scope
        FROM [Gold].[Fact_Recalls] fr
        LEFT JOIN #has_next_appt na
            ON  na.pk_Patient = fr.fk_Patient
            AND na.Tenant_ID  = fr.Tenant_ID
        WHERE fr.fk_Patient IS NOT NULL
        AND (
            fr.fk_Date_First_Reminder IS NOT NULL
            OR (
                fr.Due_Date IS NOT NULL
                AND fr.Due_Date >= @ro_back
                AND fr.Due_Date <= @ro_ahead
            )
        )
        GROUP BY fr.Tenant_ID, fr.fk_Patient;

        IF NOT EXISTS (
            SELECT 1 FROM [Gold].[Fact_KPI_Snapshot]
            WHERE [Metric] = 'retention_outlook' AND [fk_Date] = @ro_fk_date
        )
        BEGIN
            INSERT INTO [Gold].[Fact_KPI_Snapshot] (
                Tenant_ID, fk_Practice_Site, fk_Practitioner,
                Metric, fk_Date, Snapshot_Grain,
                Value, DW_Created_At
            )
            SELECT
                rs.Tenant_ID,
                ISNULL(dps.pk_Practice_Site, -1)                         AS fk_Practice_Site,
                -1                                                        AS fk_Practitioner,
                'retention_outlook'                                       AS Metric,
                @ro_fk_date                                               AS fk_Date,
                'weekly'                                                  AS Snapshot_Grain,
                CAST(SUM(rs.Has_Booking) AS DECIMAL(18,4))
                    / NULLIF(CAST(COUNT(*) AS DECIMAL(18,4)), 0)         AS Value,
                SYSUTCDATETIME()
            FROM #recall_scope rs
            LEFT JOIN Gold.Dim_Patients       dp  ON  dp.pk_Patient  = rs.fk_Patient
                                                  AND dp.Tenant_ID   = rs.Tenant_ID
            LEFT JOIN Gold.Dim_Practice_Sites dps ON  dps.Site_ID    = dp.Site_ID
                                                  AND dps.Tenant_ID  = dp.Tenant_ID
            GROUP BY rs.Tenant_ID, dps.pk_Practice_Site;

            SET @My_Inserts = @My_Inserts + @@ROWCOUNT;
        END

        DROP TABLE #has_next_appt;
        DROP TABLE #recall_scope;

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
