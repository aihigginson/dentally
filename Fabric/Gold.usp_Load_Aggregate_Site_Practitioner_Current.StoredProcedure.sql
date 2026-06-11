--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Aggregate_Site_Practitioner_Current] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Site_Practitioner_Current
--  Author           :  AIH
--  Initial Date     :  07/05/2026
--  History          :
--    *01     07/05/2026  AIH  Initial Release
--    *02     11/06/2026  AIH  Add Next_7_Days_Available_Mins / Next_7_Days_Booked_Mins
--  Notes:
--    Grain  : Site × Practitioner × Tenant  (current forward-looking diary availability)
--    Pattern: Full DELETE + INSERT each run.
--    pk      generated via ROW_NUMBER() — no IDENTITY column.
--    Days_Until_Next_30_Mins    : days from today until the practitioner's first future diary
--                                 day where (Available_Clinical_Mins - booked appointment mins) >= 30.
--    Days_Until_Next_1_Hour_Free: same threshold at 60 minutes.
--    Site is derived from Dim_Practitioners.Site_ID (the practitioner's home site).
--    If a practitioner works across multiple sites, only the home site is represented;
--    extend via Fact_Appointments site attribution if cross-site coverage is needed.
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
          AND dd.Full_Date > @Today;

        -- ── Earliest free slot per practitioner ──────────────────────────────
        SELECT
            f.fk_Practitioner,
            f.Tenant_ID,
            MIN(CASE WHEN f.Free_Mins >= 30
                     THEN DATEDIFF(DAY, @Today, dd.Full_Date) END) AS Days_Until_Next_30_Mins,
            MIN(CASE WHEN f.Free_Mins >= 60
                     THEN DATEDIFF(DAY, @Today, dd.Full_Date) END) AS Days_Until_Next_1_Hour_Free
        INTO #slots
        FROM #free f
        JOIN Gold.Dim_Date dd ON dd.pk_Date = f.fk_Date
        GROUP BY f.fk_Practitioner, f.Tenant_ID;

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

        -- ── Site spine from Dim_Practitioners ───────────────────────────────
        SELECT
            dps.pk_Practice_Site                        AS fk_Site,
            dpr.pk_Practitioner                         AS fk_Practitioner,
            dpr.Tenant_ID,
            s.Days_Until_Next_30_Mins,
            s.Days_Until_Next_1_Hour_Free,
            w.Available_Mins_7d             AS Next_7_Days_Available_Mins,
            w.Booked_Mins_7d                AS Next_7_Days_Booked_Mins
        INTO #src
        FROM Gold.Dim_Practitioners dpr
        LEFT JOIN Gold.Dim_Practice_Sites dps ON dps.Site_ID   = dpr.Site_ID
                                              AND dps.Tenant_ID = dpr.Tenant_ID
        LEFT JOIN #slots s ON s.fk_Practitioner = dpr.pk_Practitioner
                           AND s.Tenant_ID       = dpr.Tenant_ID
        LEFT JOIN #week  w ON w.fk_Practitioner = dpr.pk_Practitioner
                           AND w.Tenant_ID       = dpr.Tenant_ID
        WHERE dpr.pk_Practitioner > 0;   -- exclude unknown (-1) seed row

        -- ── Full rebuild ─────────────────────────────────────────────────────
        DELETE FROM Gold.Aggregate_Site_Practitioner_Current;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Aggregate_Site_Practitioner_Current (
            pk_Site_Practitioner_Current,
            fk_Site, fk_Practitioner, Tenant_ID,
            Days_Until_Next_30_Mins, Days_Until_Next_1_Hour_Free,
            Next_7_Days_Available_Mins, Next_7_Days_Booked_Mins,
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
            SYSUTCDATETIME(),
            SYSUTCDATETIME()
        FROM #src s;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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
