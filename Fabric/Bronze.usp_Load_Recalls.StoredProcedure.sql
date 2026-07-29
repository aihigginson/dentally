--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_Recalls] @Tenant_ID=1, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Recalls
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     13/05/2026  AIH Add First_Reminder_Sent_At from Stage
--    *03     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *04     16/05/2026  AIH Fix field names (recall_date); add Practitioner_ID, Site_ID, Interval_Months, Notes, Created_At, Updated_At; remove non-existent fields
--    *05     19/05/2026  AIH Full realign to Dentally API shape: due_date; all reminder fields;
--                            appointment_id, recall_method, times_contacted, run_date,
--                            workflow_status, workflow_stage_id, prebooked;
--                            remove interval_months, notes, created_at, updated_at (not in API)
--    *06     19/05/2026  AIH Add First_Reminder_ID, Second_Reminder_ID
--    *07     20/05/2026  AIH Add first_reminder_id/second_reminder_id (NULL) to gen_recalls() output
--    *08     29/07/2026  AIH Prune to latest DENTIST + latest HYGIENE recall per patient (drop older/
--                            actioned cycles) -- Dentally deletes a recall on reattendance so history
--                            has no ongoing value; keeps Bronze + downstream Fact_Recalls at ~2 rows/patient
--    *09     29/07/2026  AIH Capture Updated_At from Stage so the ingest can pull recalls incrementally
--                            (updated_after watermark) instead of a full load -- see build_Ingest WM dict
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Recalls]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Recalls]
(
      @Tenant_ID    INT
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id            AS INT)            AS Tenant_ID
            , LEFT(id,                        255)             AS ID
            , TRY_CAST(patient_id           AS DECIMAL(18,4))  AS Patient_ID
            , LEFT(appointment_id,            255)             AS Appointment_ID
            , LEFT(due_date,                  255)             AS Due_Date
            , LEFT(recall_type,               255)             AS Recall_Type
            , LEFT(recall_method,             255)             AS Recall_Method
            , LEFT(status,                    255)             AS Status
            , LEFT(prebooked,                 10)              AS Prebooked
            , LEFT(first_reminder_sent_at,    255)             AS First_Reminder_Sent_At
            , LEFT(first_reminder_type,       255)             AS First_Reminder_Type
            , LEFT(second_reminder_sent_at,   255)             AS Second_Reminder_Sent_At
            , LEFT(second_reminder_type,      255)             AS Second_Reminder_Type
            , LEFT(last_reminded_at,          255)             AS Last_Reminded_At
            , LEFT(latest_reminder_type,      255)             AS Latest_Reminder_Type
            , TRY_CAST(times_contacted      AS DECIMAL(18,4))  AS Times_Contacted
            , LEFT(run_date,                  255)             AS Run_Date
            , LEFT(workflow_status,           255)             AS Workflow_Status
            , LEFT(workflow_stage_id,         255)             AS Workflow_Stage_ID
            , LEFT(first_reminder_id,         255)            AS First_Reminder_ID
            , LEFT(second_reminder_id,        255)            AS Second_Reminder_ID
            , LEFT(updated_at,                255)            AS Updated_At
        INTO #src
        FROM Stage.Recalls
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Patient_ID              = src.Patient_ID
            , tgt.Appointment_ID          = src.Appointment_ID
            , tgt.Due_Date                = src.Due_Date
            , tgt.Recall_Type             = src.Recall_Type
            , tgt.Recall_Method           = src.Recall_Method
            , tgt.Status                  = src.Status
            , tgt.Prebooked               = src.Prebooked
            , tgt.First_Reminder_Sent_At  = src.First_Reminder_Sent_At
            , tgt.First_Reminder_Type     = src.First_Reminder_Type
            , tgt.Second_Reminder_Sent_At = src.Second_Reminder_Sent_At
            , tgt.Second_Reminder_Type    = src.Second_Reminder_Type
            , tgt.Last_Reminded_At        = src.Last_Reminded_At
            , tgt.Latest_Reminder_Type    = src.Latest_Reminder_Type
            , tgt.Times_Contacted         = src.Times_Contacted
            , tgt.Run_Date                = src.Run_Date
            , tgt.Workflow_Status         = src.Workflow_Status
            , tgt.Workflow_Stage_ID       = src.Workflow_Stage_ID
            , tgt.First_Reminder_ID       = src.First_Reminder_ID
            , tgt.Second_Reminder_ID      = src.Second_Reminder_ID
            , tgt.Updated_At              = src.Updated_At
            , tgt.DW_Loaded_At            = SYSUTCDATETIME()
        FROM Bronze.Recalls AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Recalls (
            Tenant_ID, ID, Patient_ID, Appointment_ID, Due_Date,
            Recall_Type, Recall_Method, Status, Prebooked,
            First_Reminder_Sent_At, First_Reminder_Type,
            Second_Reminder_Sent_At, Second_Reminder_Type,
            Last_Reminded_At, Latest_Reminder_Type,
            Times_Contacted, Run_Date, Workflow_Status, Workflow_Stage_ID,
            First_Reminder_ID, Second_Reminder_ID,
            Updated_At,
            DW_Loaded_At
        )
        SELECT
            src.Tenant_ID, src.ID, src.Patient_ID, src.Appointment_ID, src.Due_Date,
            src.Recall_Type, src.Recall_Method, src.Status, src.Prebooked,
            src.First_Reminder_Sent_At, src.First_Reminder_Type,
            src.Second_Reminder_Sent_At, src.Second_Reminder_Type,
            src.Last_Reminded_At, src.Latest_Reminder_Type,
            src.Times_Contacted, src.Run_Date, src.Workflow_Status, src.Workflow_Stage_ID,
            src.First_Reminder_ID, src.Second_Reminder_ID,
            src.Updated_At,
            SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Recalls tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        -- Keep only the CURRENT cycle: the latest DENTIST + latest HYGIENE recall per patient, dropping
        -- older/actioned cycles. Dentally deletes a recall once the patient reattends for that type, so
        -- historical cycles carry no ongoing signal; retaining one-per-type holds Bronze (and every
        -- downstream Fact_Recalls row) at ~2 rows/patient. Type split matches Fact_Recalls: anything
        -- mentioning 'hygien' is the hygiene recall, everything else (incl. plain 'Dentist') is the
        -- dentist recall. "Latest" = furthest-out Due_Date (the active cycle); ID is a stable tiebreak.
        ;WITH ranked AS (
            SELECT ID,
                   ROW_NUMBER() OVER (
                       PARTITION BY Tenant_ID, Patient_ID,
                                    CASE WHEN Recall_Type LIKE '%ygien%' THEN 'H' ELSE 'D' END
                       ORDER BY TRY_CAST(Due_Date AS date) DESC, ID DESC) AS rn
            FROM Bronze.Recalls
            WHERE Tenant_ID = @Tenant_ID
        )
        DELETE FROM Bronze.Recalls
        WHERE Tenant_ID = @Tenant_ID
          AND ID IN (SELECT ID FROM ranked WHERE rn > 1);
        SET @My_Deletes = @@ROWCOUNT;

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
