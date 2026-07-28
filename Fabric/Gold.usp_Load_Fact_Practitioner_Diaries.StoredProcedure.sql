--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Practitioner_Diaries] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Practitioner_Diaries
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     30/04/2026  AIH Replace CAST AS DATETIME with datetime2(3); TIME -> TIME(0) — Fabric requires explicit precision
--    *03     01/05/2026  AIH Wrap non-date FK lookups with ISNULL(..., -1) for unknown dimension row
--    *04     19/05/2026  AIH DATEDIFF casts: datetime2(3) -> TIME; time-only strings fail TRY_CAST to datetime2 in Fabric
--    *05     19/05/2026  AIH Time extractor: test-data format is '2023-07-21T09:00.000+00:00'; strip date prefix via CHARINDEX('T')
--    *06     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *07     07/07/2026  AIH Days-worked-only filter: keep rows that are Available AND have real
--                            start/finish times. Dentally writes one diary row per practitioner per
--                            calendar day (non-working = NULL times; holiday = unavailable=1); those
--                            zero-hour rows bloated the fact and dragged down per-row hour averages.
--                            Silver retains all rows (reversible). Pairs with Bronze *05 (unavailable).
--    *08     13/07/2026  AIH Add Is_Dummy + SYNTHETIC diary entries: for (practitioner, day) with
--                            real (non-cancelled) patient appointments but NO worked diary row, insert
--                            a dummy entry spanning first->last appointment (Is_Dummy=1) so those days
--                            get a worked-hours denominator for Chair Utilisation / Diary Fill. Sourced
--                            from Silver.Appointments (no dependency on the Gold appointments fact).
--    *09     13/07/2026  AIH Dummy Available_Clinical_Mins = SUM of appointment durations (booked time)
--                            not the first->last span. The span swept in gap + block time and, once the
--                            aggregate subtracted blocks, pushed dummy-day Diary Fill to ~145% / Chair
--                            Util ~116%. Worked = booked -> Diary Fill 100% by design, Chair Util <=100%.
--                            Pairs with aggregate *09 (no block subtraction on dummy days).
--    *10     28/07/2026  AIH DEDUP BREAKS + floor Available at 0. Real Dentally data repeats the SAME
--                            break (e.g. Lunch 13:00-14:00) dozens of times per diary (no break Id at
--                            source, ingest not deduping): 40-72 identical rows seen, inflating
--                            Break_Count/Total_Break_Mins (40x60=2400) and driving Available_Clinical_Mins
--                            hugely negative (-1910) -> negative worked hours in reports. Count each
--                            DISTINCT (diary, name, start, end) once; clamp Available_Clinical_Mins >= 0.
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Fact_Practitioner_Diaries @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Practitioner_Diaries]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Practitioner_Diaries]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Practitioner_Diaries]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       smallint      = 1
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

        SELECT
            pd.Tenant_ID                                                AS Tenant_ID,
            pd.Id                                                       AS bk_Practitioner_Diary_ID,
            ISNULL(dpr.pk_Practitioner, -1)                             AS fk_Practitioner,
            dd.pk_Date                                                  AS fk_Date_Day,
            CAST(pd.Day AS DATE)                                        AS Day_Date,
            TRY_CAST(
                CASE WHEN CHARINDEX('T', NULLIF(TRIM(pd.Start_Time),'')) > 0
                     THEN LEFT(SUBSTRING(pd.Start_Time, CHARINDEX('T', pd.Start_Time)+1, 8), 5) + ':00'
                     ELSE NULLIF(TRIM(pd.Start_Time),'')
                END AS TIME(0))                                              AS Start_Time,
            TRY_CAST(
                CASE WHEN CHARINDEX('T', NULLIF(TRIM(pd.Finish_Time),'')) > 0
                     THEN LEFT(SUBSTRING(pd.Finish_Time, CHARINDEX('T', pd.Finish_Time)+1, 8), 5) + ':00'
                     ELSE NULLIF(TRIM(pd.Finish_Time),'')
                END AS TIME(0))                                              AS End_Time,
            1-CAST(ISNULL(pd.Available,0) AS BIT)                       AS Unavailable,
            CASE WHEN NULLIF(TRIM(pd.Start_Time),'') IS NOT NULL AND NULLIF(TRIM(pd.Finish_Time),'') IS NOT NULL
                 THEN DATEDIFF(MINUTE,
                        TRY_CAST(CASE WHEN CHARINDEX('T', NULLIF(TRIM(pd.Start_Time),'')) > 0 THEN LEFT(SUBSTRING(pd.Start_Time, CHARINDEX('T', pd.Start_Time)+1, 8), 5) + ':00' ELSE NULLIF(TRIM(pd.Start_Time),'') END AS TIME),
                        TRY_CAST(CASE WHEN CHARINDEX('T', NULLIF(TRIM(pd.Finish_Time),'')) > 0 THEN LEFT(SUBSTRING(pd.Finish_Time, CHARINDEX('T', pd.Finish_Time)+1, 8), 5) + ':00' ELSE NULLIF(TRIM(pd.Finish_Time),'') END AS TIME))
            END                                                         AS Session_Duration_Mins,
            COALESCE(brk.Total_Break_Mins, 0)                           AS Total_Break_Mins,
            COALESCE(brk.Break_Count, 0)                                AS Break_Count,
            CASE WHEN CAST(ISNULL(pd.Available,0) AS BIT) = 1
                      AND NULLIF(TRIM(pd.Start_Time),'') IS NOT NULL AND NULLIF(TRIM(pd.Finish_Time),'') IS NOT NULL
                 -- *10 floor at 0: session minus breaks must never be negative (belt-and-suspenders on top of the break dedup)
                 THEN CASE WHEN DATEDIFF(MINUTE,
                        TRY_CAST(CASE WHEN CHARINDEX('T', NULLIF(TRIM(pd.Start_Time),'')) > 0 THEN LEFT(SUBSTRING(pd.Start_Time, CHARINDEX('T', pd.Start_Time)+1, 8), 5) + ':00' ELSE NULLIF(TRIM(pd.Start_Time),'') END AS TIME),
                        TRY_CAST(CASE WHEN CHARINDEX('T', NULLIF(TRIM(pd.Finish_Time),'')) > 0 THEN LEFT(SUBSTRING(pd.Finish_Time, CHARINDEX('T', pd.Finish_Time)+1, 8), 5) + ':00' ELSE NULLIF(TRIM(pd.Finish_Time),'') END AS TIME))
                      - COALESCE(brk.Total_Break_Mins, 0) < 0 THEN 0
                      ELSE DATEDIFF(MINUTE,
                        TRY_CAST(CASE WHEN CHARINDEX('T', NULLIF(TRIM(pd.Start_Time),'')) > 0 THEN LEFT(SUBSTRING(pd.Start_Time, CHARINDEX('T', pd.Start_Time)+1, 8), 5) + ':00' ELSE NULLIF(TRIM(pd.Start_Time),'') END AS TIME),
                        TRY_CAST(CASE WHEN CHARINDEX('T', NULLIF(TRIM(pd.Finish_Time),'')) > 0 THEN LEFT(SUBSTRING(pd.Finish_Time, CHARINDEX('T', pd.Finish_Time)+1, 8), 5) + ':00' ELSE NULLIF(TRIM(pd.Finish_Time),'') END AS TIME))
                      - COALESCE(brk.Total_Break_Mins, 0) END
                 ELSE 0 END                                             AS Available_Clinical_Mins,
            CAST(0 AS BIT)                                              AS Is_Dummy
        INTO #src
        FROM Silver.Practitioner_Diary pd
        LEFT JOIN Gold.Dim_Practitioners dpr ON dpr.Practitioner_ID = CAST(pd.Practitioner_ID AS INT) AND dpr.Tenant_ID = pd.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd           ON dd.Full_Date        = pd.Day
        LEFT JOIN (
            -- *10 DEDUP: real Dentally data repeats the SAME break (e.g. Lunch 13:00-14:00) many times
            -- per diary (no break Id at source, ingest not deduping) -- 40-72 identical rows seen. Count
            -- each DISTINCT (diary, name, start, end) once, else Break_Count/Total_Break_Mins balloon and
            -- Available_Clinical_Mins goes hugely negative.
            SELECT
                Practitioner_Diary_ID,
                SUM(DATEDIFF(MINUTE,
                    TRY_CAST(NULLIF(TRIM(Start_Time),'') AS datetime2(3)),
                    TRY_CAST(NULLIF(TRIM(End_Time),'') AS datetime2(3))))  AS Total_Break_Mins,
                COUNT(*)                                                AS Break_Count
            FROM (
                SELECT DISTINCT Practitioner_Diary_ID, Break_Name, Start_Time, End_Time
                FROM Silver.Practitioner_Diary_Breaks
            ) b
            GROUP BY Practitioner_Diary_ID
        ) brk ON brk.Practitioner_Diary_ID = pd.Id
        -- DAYS WORKED ONLY. Dentally writes one diary row per practitioner per calendar day; a
        -- non-working day has NULL start/finish (day off) and unavailable days are flagged. We keep
        -- only actually-worked sessions (available + real times) so the fact is one-row-per-worked-day,
        -- not one-per-calendar-day. Silver retains every row (reversible). This also stops zero-hour
        -- rows dragging down any per-diary-row average of working hours.
        WHERE pd.Id IS NOT NULL
          AND CAST(ISNULL(pd.Available,0) AS BIT) = 1
          AND NULLIF(TRIM(pd.Start_Time),'')  IS NOT NULL
          AND NULLIF(TRIM(pd.Finish_Time),'') IS NOT NULL;

        -- SYNTHETIC (dummy) diary entries: (practitioner, day) with real non-cancelled patient
        -- appointments but NO worked diary row above. Available_Clinical_Mins = SUM of the appointment
        -- durations (the BOOKED time) -- NOT the first->last span, which would sweep in gap + block time
        -- and (with the aggregate's block subtraction) push Diary Fill over 100%. With worked = booked,
        -- Diary Fill on a dummy day is 100% by design and Chair Utilisation = in-chair / booked (<=100%).
        -- Start/End_Time still show the first->last window. Blocks are NOT subtracted for dummy days in
        -- the aggregate. Sourced from Silver.Appointments (no dependency on the Gold appointments fact).
        INSERT INTO #src (Tenant_ID, bk_Practitioner_Diary_ID, fk_Practitioner, fk_Date_Day, Day_Date,
                          Start_Time, End_Time, Unavailable, Session_Duration_Mins, Total_Break_Mins,
                          Break_Count, Available_Clinical_Mins, Is_Dummy)
        SELECT
            ag.Tenant_ID,
            'DUMMY-' + CAST(ag.Tenant_ID AS VARCHAR(10)) + '-' + CAST(ag.Practitioner_ID AS VARCHAR(20))
                     + '-' + CONVERT(VARCHAR(8), ag.appt_date, 112)         AS bk_Practitioner_Diary_ID,
            ISNULL(dpr.pk_Practitioner, -1)                                  AS fk_Practitioner,
            dd.pk_Date                                                      AS fk_Date_Day,
            ag.appt_date                                                    AS Day_Date,
            ag.start_t                                                      AS Start_Time,
            ag.end_t                                                        AS End_Time,
            CAST(0 AS BIT)                                                  AS Unavailable,
            ag.span_mins                                                    AS Session_Duration_Mins,
            0                                                               AS Total_Break_Mins,
            0                                                               AS Break_Count,
            ag.booked_mins                                                  AS Available_Clinical_Mins,
            CAST(1 AS BIT)                                                  AS Is_Dummy
        FROM (
            SELECT a.Tenant_ID, TRY_CAST(a.Practitioner_ID AS INT) AS Practitioner_ID,
                   CAST(LEFT(a.Start_Time,10) AS DATE) AS appt_date,
                   MIN(TRY_CAST(SUBSTRING(a.Start_Time,  CHARINDEX('T',a.Start_Time)+1,  8) AS TIME(0))) AS start_t,
                   MAX(TRY_CAST(SUBSTRING(a.Finish_Time, CHARINDEX('T',a.Finish_Time)+1, 8) AS TIME(0))) AS end_t,
                   DATEDIFF(MINUTE,
                       MIN(TRY_CAST(SUBSTRING(a.Start_Time,  CHARINDEX('T',a.Start_Time)+1,  8) AS TIME(0))),
                       MAX(TRY_CAST(SUBSTRING(a.Finish_Time, CHARINDEX('T',a.Finish_Time)+1, 8) AS TIME(0)))) AS span_mins,
                   -- BOOKED time = sum of the per-appointment durations (matches Fact Appointment_Hours),
                   -- so Diary Fill = 100% on dummy days. Prefer the source Duration; fall back to finish-start.
                   SUM(COALESCE(TRY_CAST(a.Duration AS INT),
                       DATEDIFF(MINUTE,
                           TRY_CAST(SUBSTRING(a.Start_Time,  CHARINDEX('T',a.Start_Time)+1,  8) AS TIME(0)),
                           TRY_CAST(SUBSTRING(a.Finish_Time, CHARINDEX('T',a.Finish_Time)+1, 8) AS TIME(0))))) AS booked_mins
            FROM Silver.Appointments a
            WHERE ISNULL(a.State,'') NOT IN ('Cancelled') AND a.Patient_ID IS NOT NULL
              AND CHARINDEX('T', a.Start_Time) > 0 AND CHARINDEX('T', a.Finish_Time) > 0
            GROUP BY a.Tenant_ID, TRY_CAST(a.Practitioner_ID AS INT), CAST(LEFT(a.Start_Time,10) AS DATE)
            HAVING DATEDIFF(MINUTE,
                       MIN(TRY_CAST(SUBSTRING(a.Start_Time,  CHARINDEX('T',a.Start_Time)+1,  8) AS TIME(0))),
                       MAX(TRY_CAST(SUBSTRING(a.Finish_Time, CHARINDEX('T',a.Finish_Time)+1, 8) AS TIME(0)))) > 0
        ) ag
        LEFT JOIN Gold.Dim_Practitioners dpr ON dpr.Practitioner_ID = ag.Practitioner_ID AND dpr.Tenant_ID = ag.Tenant_ID
        LEFT JOIN Gold.Dim_Date          dd  ON dd.Full_Date        = ag.appt_date
        WHERE NOT EXISTS (
            SELECT 1 FROM #src s
            WHERE s.Tenant_ID = ag.Tenant_ID
              AND s.fk_Practitioner = ISNULL(dpr.pk_Practitioner, -1)
              AND s.fk_Date_Day = dd.pk_Date
        );

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Practitioner_Diaries tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Practitioner_Diary_ID = tgt.bk_Practitioner_Diary_ID AND Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Practitioner         = src.fk_Practitioner,
            fk_Date_Day             = src.fk_Date_Day,
            Day_Date                = src.Day_Date,
            Start_Time              = src.Start_Time,
            End_Time                = src.End_Time,
            Unavailable             = src.Unavailable,
            Session_Duration_Mins   = src.Session_Duration_Mins,
            Total_Break_Mins        = src.Total_Break_Mins,
            Available_Clinical_Mins = src.Available_Clinical_Mins,
            Break_Count             = src.Break_Count,
            Is_Dummy                = src.Is_Dummy,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Fact_Practitioner_Diaries tgt
        INNER JOIN #src src ON tgt.bk_Practitioner_Diary_ID = src.bk_Practitioner_Diary_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Day] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Day_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Start_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[End_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Unavailable] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Session_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Total_Break_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Available_Clinical_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Break_Count] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Dummy] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Day] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Day_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Start_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[End_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Unavailable] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Session_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Total_Break_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Available_Clinical_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Break_Count] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Dummy] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Practitioner_Diaries (
            Tenant_ID,
            bk_Practitioner_Diary_ID,
            fk_Practitioner, fk_Date_Day,
            Day_Date, Start_Time, End_Time, Unavailable,
            Session_Duration_Mins, Total_Break_Mins, Available_Clinical_Mins, Break_Count,
            Is_Dummy,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID,
            src.bk_Practitioner_Diary_ID,
            src.fk_Practitioner, src.fk_Date_Day,
            src.Day_Date, src.Start_Time, src.End_Time, src.Unavailable,
            src.Session_Duration_Mins, src.Total_Break_Mins, src.Available_Clinical_Mins, src.Break_Count,
            src.Is_Dummy,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Practitioner_Diaries tgt WHERE tgt.bk_Practitioner_Diary_ID = src.bk_Practitioner_Diary_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
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
