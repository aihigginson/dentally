--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Aggregate_Site_Practitioner_Current] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Site_Practitioner_Current
--  Author           :  AIH
--  Initial Date     :  07/05/2026
--  History          :
--    *01     07/05/2026  AIH  Initial Release
--    *02     11/06/2026  AIH  Add Next_7_Days_Available_Mins / Next_7_Days_Booked_Mins
--    *04     31/07/2026  AIH  Days_Until_Next_30/60 counted in SESSION days (practitioner's own
--                             working days) not calendar days; #free now session days only.
--    *03     30/07/2026  AIH  Fold in Day Book action counts (Open Plans / Cancellations /
--                             DNAs / Recalls to action + Days Until 30-min text), split by
--                             site. Spine now = home site UNION any site with outstanding
--                             actions, so multi-site practitioners split. Retires the separate
--                             Aggregate_Practitioner_Day_Book table.
--  Notes:
--    Grain  : Site × Practitioner × Tenant  (current forward-looking diary availability + actions)
--    Pattern: Full DELETE + INSERT each run.
--    pk      generated via ROW_NUMBER() — no IDENTITY column.
--    Days_Until_Next_30_Mins    : the practitioner's SESSION-day count until the first future
--                                 diary day where (Available_Clinical_Mins - booked appointment
--                                 mins) >= 30 -- i.e. their Nth working day, not calendar days.
--    Days_Until_Next_1_Hour_Free: same threshold at 60 minutes.
--    Availability (Days_Until_*, Next_7_Days_*) belongs to the practitioner's diary, so it is
--    attached to the HOME-site row only (NULL on other-site rows) to avoid double-counting.
--    Action counts are split by the fact's own fk_Practice_Site (recalls via Fact_Recalls.
--    fk_Practice_Site, derived from the patient's site).
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Load_Aggregate_Site_Practitioner_Current
--               @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Aggregate_Site_Practitioner_Current]
GO
CREATE PROCEDURE [Gold].[usp_Load_Aggregate_Site_Practitioner_Current]
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

        DECLARE @Today    DATE = CAST(SYSUTCDATETIME() AS DATE);
        DECLARE @Week_End DATE = DATEADD(DAY, 7, @Today);

        -- ── Booked minutes per practitioner per future day ───────────────────
        -- Sum non-cancelled appointment durations against each diary day.
        SELECT
            apt.fk_Practitioner,
            apt.fk_Date_Start                           AS fk_Date,
            apt.Tenant_ID,
            SUM(ISNULL(apt.Duration_Mins, 0))           AS Booked_Mins
        INTO #booked
        FROM Gold.Fact_Appointments apt
        JOIN Gold.Dim_Date dd ON dd.pk_Date = apt.fk_Date_Start
        WHERE apt.Is_Cancelled = 0
          AND dd.Full_Date > @Today
        GROUP BY apt.fk_Practitioner, apt.fk_Date_Start, apt.Tenant_ID;

        -- ── Diary availability per practitioner per future day ───────────────
        SELECT
            fpd.fk_Practitioner,
            fpd.fk_Date_Day                             AS fk_Date,
            fpd.Tenant_ID,
            ISNULL(fpd.Available_Clinical_Mins, 0)
                - ISNULL(b.Booked_Mins, 0)              AS Free_Mins
        INTO #free
        FROM Gold.Fact_Practitioner_Diaries fpd
        JOIN Gold.Dim_Date dd ON dd.pk_Date = fpd.fk_Date_Day
        LEFT JOIN #booked b ON b.fk_Practitioner = fpd.fk_Practitioner
                            AND b.fk_Date         = fpd.fk_Date_Day
                            AND b.Tenant_ID       = fpd.Tenant_ID
        WHERE fpd.Unavailable = 0
          AND ISNULL(fpd.Available_Clinical_Mins, 0) > 0   -- session days only (has clinical time)
          AND dd.Full_Date > @Today;

        -- ── Earliest free slot per practitioner (counted in SESSION days) ─────
        -- "Days Until Next 30/60 Free" = the position of the first future session day
        -- with >= the threshold of free clinical time, counting only the days the
        -- practitioner actually has sessions (diary rows) -- NOT calendar days. So a
        -- 2-day-a-week practitioner booked for weeks reads e.g. 12 (their 12th session)
        -- rather than 52 calendar days.
        SELECT
            r.fk_Practitioner,
            r.Tenant_ID,
            MIN(CASE WHEN r.Free_Mins >= 30 THEN r.session_rank END) AS Days_Until_Next_30_Mins,
            MIN(CASE WHEN r.Free_Mins >= 60 THEN r.session_rank END) AS Days_Until_Next_1_Hour_Free
        INTO #slots
        FROM (
            SELECT f.fk_Practitioner, f.Tenant_ID, f.Free_Mins,
                   ROW_NUMBER() OVER (PARTITION BY f.fk_Practitioner, f.Tenant_ID
                                      ORDER BY dd.Full_Date) AS session_rank
            FROM #free f
            JOIN Gold.Dim_Date dd ON dd.pk_Date = f.fk_Date
        ) r
        GROUP BY r.fk_Practitioner, r.Tenant_ID;

        -- ── Next-7-day available and booked minutes per practitioner ────────
        -- Includes today; sums diary availability and non-cancelled booked mins.
        SELECT
            fpd.fk_Practitioner,
            fpd.Tenant_ID,
            SUM(ISNULL(fpd.Available_Clinical_Mins, 0))     AS Available_Mins_7d,
            ISNULL(SUM(b7.Booked_Mins), 0)                  AS Booked_Mins_7d
        INTO #week
        FROM Gold.Fact_Practitioner_Diaries fpd
        JOIN Gold.Dim_Date dd ON dd.pk_Date = fpd.fk_Date_Day
        LEFT JOIN (
            SELECT apt.fk_Practitioner, apt.fk_Date_Start AS fk_Date, apt.Tenant_ID,
                   SUM(ISNULL(apt.Duration_Mins, 0))         AS Booked_Mins
            FROM Gold.Fact_Appointments apt
            JOIN Gold.Dim_Date dd2 ON dd2.pk_Date = apt.fk_Date_Start
            WHERE apt.Is_Cancelled = 0
              AND dd2.Full_Date >= @Today
              AND dd2.Full_Date <  @Week_End
            GROUP BY apt.fk_Practitioner, apt.fk_Date_Start, apt.Tenant_ID
        ) b7 ON b7.fk_Practitioner = fpd.fk_Practitioner
             AND b7.fk_Date          = fpd.fk_Date_Day
             AND b7.Tenant_ID        = fpd.Tenant_ID
        WHERE fpd.Unavailable = 0
          AND dd.Full_Date >= @Today
          AND dd.Full_Date <  @Week_End
        GROUP BY fpd.fk_Practitioner, fpd.Tenant_ID;

        -- ── Home (primary) site per practitioner ─────────────────────────────
        -- Availability metrics belong to the practitioner's diary, not a site;
        -- they are attached to this home-site row only (see #src CASE below).
        SELECT
            dpr.pk_Practitioner                         AS fk_Practitioner,
            dpr.Tenant_ID,
            ISNULL(dps.pk_Practice_Site, -1)            AS fk_Home_Site
        INTO #home
        FROM Gold.Dim_Practitioners dpr
        LEFT JOIN Gold.Dim_Practice_Sites dps ON dps.Site_ID   = dpr.Site_ID
                                              AND dps.Tenant_ID = dpr.Tenant_ID
        WHERE dpr.pk_Practitioner > 0;   -- exclude unknown (-1) seed row

        -- ── Day Book action counts per (site × practitioner) ─────────────────
        -- Each matches its Day Book detail-page filter. Split by the fact's own
        -- fk_Practice_Site so a multi-site practitioner's actions land at the
        -- right site (recalls now carry fk_Practice_Site, derived from the patient).
        SELECT Tenant_ID, ISNULL(fk_Practice_Site,-1) AS fk_Site, fk_Practitioner, COUNT(1) AS cnt
        INTO #op
        FROM Gold.Fact_Treatment_Plans
        WHERE Course_Status IN ('In Progress', 'Open - No Appointment')
        GROUP BY Tenant_ID, ISNULL(fk_Practice_Site,-1), fk_Practitioner;

        -- Active patients only (exclude inactive) -- matches the detail-page filter.
        SELECT a.Tenant_ID, ISNULL(a.fk_Practice_Site,-1) AS fk_Site, a.fk_Practitioner, COUNT(1) AS cnt
        INTO #cx
        FROM Gold.Fact_Appointments a
        JOIN Gold.Dim_Patients dp ON dp.pk_Patient = a.fk_Patient AND dp.Active = 1
        WHERE a.Is_Cancelled = 1 AND a.Rebooked_Status = 'Not Rebooked'
        GROUP BY a.Tenant_ID, ISNULL(a.fk_Practice_Site,-1), a.fk_Practitioner;

        SELECT a.Tenant_ID, ISNULL(a.fk_Practice_Site,-1) AS fk_Site, a.fk_Practitioner, COUNT(1) AS cnt
        INTO #dn
        FROM Gold.Fact_Appointments a
        JOIN Gold.Dim_Patients dp ON dp.pk_Patient = a.fk_Patient AND dp.Active = 1
        WHERE a.Is_DNA = 1 AND a.Rebooked_Status = 'Not Rebooked'
        GROUP BY a.Tenant_ID, ISNULL(a.fk_Practice_Site,-1), a.fk_Practitioner;

        SELECT Tenant_ID, ISNULL(fk_Practice_Site,-1) AS fk_Site, fk_Practitioner, COUNT(1) AS cnt
        INTO #rc
        FROM Gold.Fact_Recalls
        WHERE Retention_Outlook_In_Scope = 1 AND Is_Booked = 0
        GROUP BY Tenant_ID, ISNULL(fk_Practice_Site,-1), fk_Practitioner;

        -- ── Site × practitioner spine ────────────────────────────────────────
        -- Union of the home site (for availability) with any site where the
        -- practitioner has outstanding Day Book actions, so multi-site
        -- practitioners split correctly.
        SELECT DISTINCT Tenant_ID, fk_Site, fk_Practitioner
        INTO #spine
        FROM (
            SELECT Tenant_ID, fk_Home_Site AS fk_Site, fk_Practitioner FROM #home
            UNION SELECT Tenant_ID, fk_Site, fk_Practitioner FROM #op
            UNION SELECT Tenant_ID, fk_Site, fk_Practitioner FROM #cx
            UNION SELECT Tenant_ID, fk_Site, fk_Practitioner FROM #dn
            UNION SELECT Tenant_ID, fk_Site, fk_Practitioner FROM #rc
        ) u
        WHERE fk_Practitioner > 0;

        SELECT
            sp.fk_Site,
            sp.fk_Practitioner,
            sp.Tenant_ID,
            -- availability on the home-site row only (not double-counted across sites)
            CASE WHEN sp.fk_Site = h.fk_Home_Site THEN s.Days_Until_Next_30_Mins     END AS Days_Until_Next_30_Mins,
            CASE WHEN sp.fk_Site = h.fk_Home_Site THEN s.Days_Until_Next_1_Hour_Free END AS Days_Until_Next_1_Hour_Free,
            CASE WHEN sp.fk_Site = h.fk_Home_Site THEN w.Available_Mins_7d           END AS Next_7_Days_Available_Mins,
            CASE WHEN sp.fk_Site = h.fk_Home_Site THEN w.Booked_Mins_7d              END AS Next_7_Days_Booked_Mins,
            CAST(ISNULL(op.cnt, 0) AS VARCHAR(10))                                       AS Open_Plans,
            CAST(ISNULL(cx.cnt, 0) AS VARCHAR(10))                                       AS Cancellations_To_Rebook,
            CAST(ISNULL(dn.cnt, 0) AS VARCHAR(10))                                       AS DNAs_To_Rebook,
            CAST(ISNULL(rc.cnt, 0) AS VARCHAR(10))                                       AS Recalls_To_Action,
            CASE WHEN sp.fk_Site = h.fk_Home_Site
                 THEN CAST(s.Days_Until_Next_30_Mins AS VARCHAR(10)) END                 AS Days_Until_Next_30_Free
        INTO #src
        FROM #spine sp
        LEFT JOIN #home  h ON h.fk_Practitioner = sp.fk_Practitioner AND h.Tenant_ID = sp.Tenant_ID
        LEFT JOIN #slots s ON s.fk_Practitioner = sp.fk_Practitioner AND s.Tenant_ID = sp.Tenant_ID
        LEFT JOIN #week  w ON w.fk_Practitioner = sp.fk_Practitioner AND w.Tenant_ID = sp.Tenant_ID
        LEFT JOIN #op op ON op.Tenant_ID=sp.Tenant_ID AND op.fk_Site=sp.fk_Site AND op.fk_Practitioner=sp.fk_Practitioner
        LEFT JOIN #cx cx ON cx.Tenant_ID=sp.Tenant_ID AND cx.fk_Site=sp.fk_Site AND cx.fk_Practitioner=sp.fk_Practitioner
        LEFT JOIN #dn dn ON dn.Tenant_ID=sp.Tenant_ID AND dn.fk_Site=sp.fk_Site AND dn.fk_Practitioner=sp.fk_Practitioner
        LEFT JOIN #rc rc ON rc.Tenant_ID=sp.Tenant_ID AND rc.fk_Site=sp.fk_Site AND rc.fk_Practitioner=sp.fk_Practitioner;

        -- ── Full rebuild ─────────────────────────────────────────────────────
        DELETE FROM Gold.Aggregate_Site_Practitioner_Current;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Aggregate_Site_Practitioner_Current (
            pk_Site_Practitioner_Current,
            fk_Site, fk_Practitioner, Tenant_ID,
            Days_Until_Next_30_Mins, Days_Until_Next_1_Hour_Free,
            Next_7_Days_Available_Mins, Next_7_Days_Booked_Mins,
            Open_Plans, Cancellations_To_Rebook, DNAs_To_Rebook,
            Recalls_To_Action, Days_Until_Next_30_Free,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY s.Tenant_ID, s.fk_Site, s.fk_Practitioner)
                                                        AS pk_Site_Practitioner_Current,
            s.fk_Site,
            s.fk_Practitioner,
            s.Tenant_ID,
            s.Days_Until_Next_30_Mins,
            s.Days_Until_Next_1_Hour_Free,
            s.Next_7_Days_Available_Mins,
            s.Next_7_Days_Booked_Mins,
            s.Open_Plans,
            s.Cancellations_To_Rebook,
            s.DNAs_To_Rebook,
            s.Recalls_To_Action,
            s.Days_Until_Next_30_Free,
            SYSUTCDATETIME(),
            SYSUTCDATETIME()
        FROM #src s;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
        DROP TABLE #spine;
        DROP TABLE #home;
        DROP TABLE #op;
        DROP TABLE #cx;
        DROP TABLE #dn;
        DROP TABLE #rc;
        DROP TABLE #slots;
        DROP TABLE #week;
        DROP TABLE #free;
        DROP TABLE #booked;

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
