--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Recalls] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Recalls
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Wrap non-date FK lookups with ISNULL(..., -1) for unknown dimension row
--    *03     20/05/2026  AIH Times_Contacted stored as VARCHAR in Silver — route through FLOAT before INT cast
--    *04     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *05     20/05/2026  AIH Pre-compute Is_In_Scope, Is_Booked, Overdue_Band to replace heavy DAX;
--                            join Silver.Patient_Stats for Is_Patient_Booked
--    *08     29/05/2026  AIH Add Retention_Outlook_In_Scope and Retention_Outlook_Booked: pre-computed
--                            flags for Retention Outlook; KPI Snapshot uses these instead of temp tables
--    *07     29/05/2026  AIH Add Recall_Status: single derived status column (Booked / 2nd Reminder /
--                            1st Reminder / Overdue / Not Yet Due) in precedence order
--    *06     20/05/2026  AIH Is_Booked: patient-level lookup against Silver.Appointments
--                            (any future non-cancelled appt); drop Is_Patient_Booked and
--                            Appointment_ID-based join; drop enrichment cols
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Fact_Recalls @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Recalls]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Recalls]
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

        DECLARE @Today     DATE = CAST(SYSUTCDATETIME() AS DATE);
        DECLARE @ScopeFrom DATE = DATEADD(MONTH, -24, @Today);
        DECLARE @ScopeTo   DATE = DATEADD(MONTH,   1, @Today);

        -- Patient's soonest upcoming non-cancelled/DNA appointment
        -- Start_Time is stored as ISO 8601 with tz offset (e.g. "2026-07-01T09:00:00.000+00:00")
        -- TRY_CAST to DATETIMEOFFSET handles the +00:00 suffix; plain DATETIME2 cast returns NULL.
        SELECT Patient_ID, Tenant_ID, State, Booked_Via_API, Start_Time, Pending_At
        INTO #next_appt
        FROM (
            SELECT
                Patient_ID, Tenant_ID, State, Booked_Via_API, Start_Time, Pending_At,
                ROW_NUMBER() OVER (
                    PARTITION BY Patient_ID, Tenant_ID
                    ORDER BY TRY_CAST(NULLIF(TRIM(Start_Time),'') AS DATETIMEOFFSET(3))
                ) AS rn
            FROM Silver.Appointments
            WHERE NULLIF(TRIM(State),'') NOT IN ('cancelled','did_not_attend','completed')
              AND CAST(TRY_CAST(NULLIF(TRIM(Start_Time),'') AS DATETIMEOFFSET(3)) AS DATE) >= @Today
        ) x
        WHERE rn = 1;

        SELECT
            r.Tenant_ID                                                     AS Tenant_ID,
            r.Id                                                            AS bk_Recall_ID,
            ISNULL(dpat.pk_Patient, -1)                                     AS fk_Patient,
            dd_due.pk_Date                                                  AS fk_Date_Due,
            dd_run.pk_Date                                                  AS fk_Date_Run,
            dd_fr.pk_Date                                                   AS fk_Date_First_Reminder,
            dd_sr.pk_Date                                                   AS fk_Date_Second_Reminder,
            dd_lr.pk_Date                                                   AS fk_Date_Last_Reminded,
            NULLIF(TRIM(r.Appointment_ID),'')                               AS Appointment_ID,
            NULLIF(TRIM(r.Recall_Type),'')                                  AS Recall_Type,
            NULLIF(TRIM(r.Recall_Method),'')                                AS Recall_Method,
            NULLIF(TRIM(r.Status),'')                                       AS Status,
            NULLIF(TRIM(r.Workflow_Status),'')                              AS Workflow_Status,
            NULLIF(TRIM(r.Workflow_Stage_ID),'')                            AS Workflow_Stage_ID,
            NULLIF(TRIM(r.First_Reminder_Type),'')                          AS First_Reminder_Type,
            NULLIF(TRIM(r.Second_Reminder_Type),'')                         AS Second_Reminder_Type,
            NULLIF(TRIM(r.Latest_Reminder_Type),'')                         AS Latest_Reminder_Type,
            ISNULL(CAST(ROUND(TRY_CAST(r.Times_Contacted AS FLOAT), 0) AS INT), 0) AS Times_Contacted,
            CAST(r.Due_Date AS DATE)                                        AS Due_Date,
            TRY_CAST(r.Run_Date AS DATE)                                    AS Run_Date,
            CASE WHEN r.Due_Date IS NOT NULL
                      AND NULLIF(TRIM(r.Status),'') NOT IN ('booked','completed')
                 THEN DATEDIFF(DAY, r.Due_Date, @Today)
            END                                                             AS Days_Overdue,
            -- ── Retention Outlook pre-computed flags ──────────────────────────
            -- Is_In_Scope: recall falls within the Retention Outlook window.
            -- Matches the DAX window: first reminder sent OR due in [-24m, +1m].
            CAST(CASE
                WHEN NULLIF(TRIM(r.First_Reminder_Sent_At),'') IS NOT NULL    THEN 1
                WHEN r.Due_Date BETWEEN @ScopeFrom AND @ScopeTo                THEN 1
                ELSE 0
            END AS BIT)                                                     AS Is_In_Scope,
            CAST(CASE
                WHEN NULLIF(TRIM(r.First_Reminder_Sent_At),'') IS NOT NULL    THEN 1
                ELSE 0
            END AS BIT)                                                     AS Is_Reminder_Sent,
            -- Is_Booked_Via_Recall: Appointment_ID is set on the recall record
            CAST(CASE
                WHEN NULLIF(TRIM(r.Appointment_ID),'') IS NOT NULL            THEN 1
                ELSE 0
            END AS BIT)                                                     AS Is_Booked_Via_Recall,
            -- Is_Booked: patient has a future non-cancelled appointment
            CAST(CASE
                WHEN na.Patient_ID IS NOT NULL                                THEN 1
                ELSE 0
            END AS BIT)                                                     AS Is_Booked,
            -- Retention Outlook pre-computed flags (aggregated by KPI Snapshot SP per patient then per site)
            CAST(CASE
                WHEN NULLIF(TRIM(r.First_Reminder_Sent_At),'') IS NOT NULL    THEN 1
                WHEN r.Due_Date BETWEEN @ScopeFrom AND @ScopeTo                THEN 1
                ELSE 0
            END AS INT)                                                     AS Retention_Outlook_In_Scope,
            CAST(CASE
                WHEN NULLIF(TRIM(r.Appointment_ID),'') IS NOT NULL             THEN 1
                WHEN na.Patient_ID IS NOT NULL                                  THEN 1
                ELSE 0
            END AS INT)                                                     AS Retention_Outlook_Booked,
            -- Overdue_Band: pre-bucketed for bar charts — avoids SWITCH on Days_Overdue in DAX
            CASE
                WHEN r.Due_Date IS NULL                                                           THEN NULL
                WHEN NULLIF(TRIM(r.Status),'') IN ('booked','completed','attended')               THEN 'Booked'
                WHEN DATEDIFF(DAY, r.Due_Date, @Today) <= 0                                       THEN 'Upcoming'
                WHEN DATEDIFF(DAY, r.Due_Date, @Today) <= 30                                      THEN '01-30 Days'
                WHEN DATEDIFF(DAY, r.Due_Date, @Today) <= 90                                      THEN '31-90 Days'
                WHEN DATEDIFF(DAY, r.Due_Date, @Today) <= 180                                     THEN '91-180 Days'
                ELSE                                                                               '181+ Days'
            END                                                             AS Overdue_Band,
            -- Recall_Status: single actionable label in precedence order
            CASE
                WHEN na.Patient_ID IS NOT NULL  THEN 'Booked'
                WHEN dd_sr.pk_Date > 0          THEN '2nd Reminder'
                WHEN dd_fr.pk_Date > 0          THEN '1st Reminder'
                WHEN r.Due_Date < @Today        THEN 'Overdue'
                ELSE                                 'Not Yet Due'
            END                                                             AS Recall_Status,
            -- ── Appointment enrichment ────────────────────────────────────────────
            dd_ab.pk_Date                                                   AS fk_Date_Appt_Booked,
            NULLIF(TRIM(na.State),'')                                       AS Appt_State,
            na.Booked_Via_API                                               AS Appt_Booked_Via_API,
            CAST(TRY_CAST(NULLIF(TRIM(na.Start_Time),'') AS DATETIMEOFFSET(3)) AS DATETIME2(3)) AS Appt_Start_Time,
            CASE
                WHEN NULLIF(TRIM(r.First_Reminder_Sent_At),'') IS NOT NULL
                     AND NULLIF(TRIM(na.Pending_At),'') IS NOT NULL
                THEN DATEDIFF(DAY,
                     TRY_CAST(NULLIF(TRIM(r.First_Reminder_Sent_At),'') AS DATE),
                     TRY_CAST(NULLIF(TRIM(na.Pending_At),'') AS DATE))
            END                                                             AS Days_Recall_To_Booking
        INTO #src
        FROM Silver.Recalls r
        LEFT JOIN Gold.Dim_Patients dpat  ON dpat.Patient_ID  = r.Patient_ID  AND dpat.Tenant_ID = r.Tenant_ID
        LEFT JOIN #next_appt na           ON na.Patient_ID    = r.Patient_ID  AND na.Tenant_ID   = r.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_ab     ON dd_ab.Full_Date  = TRY_CAST(NULLIF(TRIM(na.Pending_At),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_due    ON dd_due.Full_Date = CAST(r.Due_Date AS DATE)
        LEFT JOIN Gold.Dim_Date dd_run    ON dd_run.Full_Date = TRY_CAST(r.Run_Date AS DATE)
        LEFT JOIN Gold.Dim_Date dd_fr     ON dd_fr.Full_Date  = TRY_CAST(NULLIF(TRIM(r.First_Reminder_Sent_At),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_sr     ON dd_sr.Full_Date  = TRY_CAST(NULLIF(TRIM(r.Second_Reminder_Sent_At),'') AS DATE)
        LEFT JOIN Gold.Dim_Date dd_lr     ON dd_lr.Full_Date  = TRY_CAST(NULLIF(TRIM(r.Last_Reminded_At),'') AS DATE)
        WHERE r.Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Recalls tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Recall_ID = tgt.bk_Recall_ID AND Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Patient               = src.fk_Patient,
            fk_Date_Due              = src.fk_Date_Due,
            fk_Date_Run              = src.fk_Date_Run,
            fk_Date_First_Reminder   = src.fk_Date_First_Reminder,
            fk_Date_Second_Reminder  = src.fk_Date_Second_Reminder,
            fk_Date_Last_Reminded    = src.fk_Date_Last_Reminded,
            Appointment_ID           = src.Appointment_ID,
            Recall_Type              = src.Recall_Type,
            Recall_Method            = src.Recall_Method,
            Status                   = src.Status,
            Workflow_Status          = src.Workflow_Status,
            Workflow_Stage_ID        = src.Workflow_Stage_ID,
            First_Reminder_Type      = src.First_Reminder_Type,
            Second_Reminder_Type     = src.Second_Reminder_Type,
            Latest_Reminder_Type     = src.Latest_Reminder_Type,
            Times_Contacted          = src.Times_Contacted,
            Due_Date                 = src.Due_Date,
            Run_Date                 = src.Run_Date,
            Days_Overdue             = src.Days_Overdue,
            Is_In_Scope              = src.Is_In_Scope,
            Is_Reminder_Sent         = src.Is_Reminder_Sent,
            Is_Booked_Via_Recall     = src.Is_Booked_Via_Recall,
            Is_Booked                    = src.Is_Booked,
            Retention_Outlook_In_Scope   = src.Retention_Outlook_In_Scope,
            Retention_Outlook_Booked     = src.Retention_Outlook_Booked,
            Overdue_Band             = src.Overdue_Band,
            Recall_Status            = src.Recall_Status,
            fk_Date_Appt_Booked      = src.fk_Date_Appt_Booked,
            Appt_State               = src.Appt_State,
            Appt_Booked_Via_API      = src.Appt_Booked_Via_API,
            Appt_Start_Time          = src.Appt_Start_Time,
            Days_Recall_To_Booking   = src.Days_Recall_To_Booking,
            DW_Updated_At            = SYSUTCDATETIME()
        FROM Gold.Fact_Recalls tgt
        INNER JOIN #src src ON tgt.bk_Recall_ID = src.bk_Recall_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Patient]             AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Due]            AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Run]            AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_First_Reminder] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Second_Reminder]AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Last_Reminded]  AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Appointment_ID]         AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Recall_Type]            AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Recall_Method]          AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Status]                 AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Workflow_Status]        AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Workflow_Stage_ID]      AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Reminder_Type]    AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Second_Reminder_Type]   AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Latest_Reminder_Type]   AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Times_Contacted]        AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Due_Date]               AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Run_Date]               AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Days_Overdue]           AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_In_Scope]              AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Reminder_Sent]         AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Booked_Via_Recall]     AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Booked]                    AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Retention_Outlook_In_Scope]  AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Retention_Outlook_Booked]    AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Overdue_Band]             AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Recall_Status]            AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Appt_Booked]      AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Appt_State]               AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Appt_Booked_Via_API]      AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Appt_Start_Time]          AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Days_Recall_To_Booking]   AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Patient]             AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Due]            AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Run]            AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_First_Reminder] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Second_Reminder]AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Last_Reminded]  AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Appointment_ID]         AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Recall_Type]            AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Recall_Method]          AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Status]                 AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Workflow_Status]        AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Workflow_Stage_ID]      AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Reminder_Type]    AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Second_Reminder_Type]   AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Latest_Reminder_Type]   AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Times_Contacted]        AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Due_Date]               AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Run_Date]               AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Days_Overdue]           AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_In_Scope]              AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Reminder_Sent]         AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Booked_Via_Recall]     AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Booked]                    AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Retention_Outlook_In_Scope]  AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Retention_Outlook_Booked]    AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Overdue_Band]             AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Recall_Status]            AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Appt_Booked]      AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Appt_State]               AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Appt_Booked_Via_API]      AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Appt_Start_Time]          AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Days_Recall_To_Booking]   AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Recalls (
            Tenant_ID,
            bk_Recall_ID,
            fk_Patient, fk_Date_Due, fk_Date_Run,
            fk_Date_First_Reminder, fk_Date_Second_Reminder, fk_Date_Last_Reminded,
            Appointment_ID, Recall_Type, Recall_Method, Status, Workflow_Status, Workflow_Stage_ID,
            First_Reminder_Type, Second_Reminder_Type, Latest_Reminder_Type,
            Times_Contacted, Due_Date, Run_Date, Days_Overdue,
            Is_In_Scope, Is_Reminder_Sent, Is_Booked_Via_Recall, Is_Booked,
            Retention_Outlook_In_Scope, Retention_Outlook_Booked,
            Overdue_Band, Recall_Status,
            fk_Date_Appt_Booked, Appt_State, Appt_Booked_Via_API, Appt_Start_Time, Days_Recall_To_Booking,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID,
            src.bk_Recall_ID,
            src.fk_Patient, src.fk_Date_Due, src.fk_Date_Run,
            src.fk_Date_First_Reminder, src.fk_Date_Second_Reminder, src.fk_Date_Last_Reminded,
            src.Appointment_ID, src.Recall_Type, src.Recall_Method, src.Status, src.Workflow_Status, src.Workflow_Stage_ID,
            src.First_Reminder_Type, src.Second_Reminder_Type, src.Latest_Reminder_Type,
            src.Times_Contacted, src.Due_Date, src.Run_Date, src.Days_Overdue,
            src.Is_In_Scope, src.Is_Reminder_Sent, src.Is_Booked_Via_Recall, src.Is_Booked,
            src.Retention_Outlook_In_Scope, src.Retention_Outlook_Booked,
            src.Overdue_Band, src.Recall_Status,
            src.fk_Date_Appt_Booked, src.Appt_State, src.Appt_Booked_Via_API, src.Appt_Start_Time, src.Days_Recall_To_Booking,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Recalls tgt WHERE tgt.bk_Recall_ID = src.bk_Recall_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #next_appt;
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
