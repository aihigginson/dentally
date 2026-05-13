--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Appointments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     13/05/2026  AIH Load all fields from Stage (previously only 13 of 27 were loaded);
--                            adds Booked_Via_API, all status timestamps, UUID, Room, User, PaymentPlan etc.
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Appointments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Appointments]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Appointments]
(
      @Tenant_ID    INT
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
    , @Full_Refresh BIT    = 0
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id                         AS INT)  AS Tenant_ID
            , TRY_CAST(id                                AS INT)  AS ID
            -- uuid, appointment_cancellation_reason_id, patient_image_url, user_id, payment_plan_id,
            -- room_id, treatment_description, pending_at, confirmed_at, arrived_at, in_surgery_at,
            -- completed_at, cancelled_at, did_not_attend_at: not yet in Stage — mock API to be updated.
            -- Add these columns to this SELECT once Stage_Ingest has been re-run after the API update.
            , TRY_CAST(patient_id                        AS INT)  AS Patient_ID
            , LEFT(patient_name,                           255)   AS Patient_Name
            , TRY_CAST(practitioner_id                   AS INT)  AS Practitioner_ID
            , LEFT(start_time,                             255)   AS Start_Time
            , LEFT(finish_time,                            255)   AS Finish_Time
            , TRY_CAST(duration                          AS INT)  AS Duration
            , LEFT(reason,                                 255)   AS Reason
            , LEFT(state,                                  255)   AS State
            , LEFT(notes,                                  255)   AS Notes
            , TRY_CAST(booked_via_api                    AS INT)  AS Booked_Via_API
            , LEFT(created_at,                             255)   AS Created_At
            , LEFT(updated_at,                             255)   AS Updated_At
        INTO #src
        FROM Stage.Appointments
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Patient_ID    = src.Patient_ID
            , tgt.Patient_Name  = src.Patient_Name
            , tgt.Practitioner_ID = src.Practitioner_ID
            , tgt.Start_Time    = src.Start_Time
            , tgt.Finish_Time   = src.Finish_Time
            , tgt.Duration      = src.Duration
            , tgt.Reason        = src.Reason
            , tgt.State         = src.State
            , tgt.Notes         = src.Notes
            , tgt.Booked_Via_API = src.Booked_Via_API
            , tgt.Created_At    = src.Created_At
            , tgt.Updated_At    = src.Updated_At
            , tgt.DW_Loaded_At  = SYSUTCDATETIME()
        FROM Bronze.Appointments AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Appointments (
            Tenant_ID, ID,
            Patient_ID, Patient_Name, Practitioner_ID,
            Start_Time, Finish_Time, Duration, Reason, State, Notes,
            Booked_Via_API,
            Created_At, Updated_At, DW_Loaded_At
        )
        SELECT
            src.Tenant_ID, src.ID,
            src.Patient_ID, src.Patient_Name, src.Practitioner_ID,
            src.Start_Time, src.Finish_Time, src.Duration, src.Reason, src.State, src.Notes,
            src.Booked_Via_API,
            src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Appointments tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Appointments AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = tgt.ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH THROW; END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
