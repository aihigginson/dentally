--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Appointments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     13/05/2026  AIH Add Booked_Via_API; strip to confirmed Stage columns pending mock API update
--    *03     14/05/2026  AIH Add all timestamp/status fields now present in Stage after mock API redeploy
--    *04     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *05     16/05/2026  AIH Add Site_ID (missing from Stage read despite being in Bronze table)
--    *06     19/05/2026  AIH Remove Site_ID, Created_At, Updated_At Stage reads (not in Dentally API)
--    *07     02/06/2026  AIH Boolean columns stored raw (VARCHAR) in Bronze; cast moved to Silver
--    *08     07/07/2026  AIH Re-add site: read practitioner_site_id (the real Dentally field, a GUID)
--                            as Practitioner_Site_ID. The *06 removal was wrong -- site IS in the API,
--                            as practitioner_site_id (not site_id). Feeds Fact_Appointments fk_Practice_Site.
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
            , LEFT(uuid,                                   255)   AS UUID
            , TRY_CAST(appointment_cancellation_reason_id AS INT) AS Appointment_Cancellation_Reason_ID
            , TRY_CAST(patient_id                        AS INT)  AS Patient_ID
            , LEFT(patient_name,                           255)   AS Patient_Name
            , LEFT(patient_image_url,                      255)   AS Patient_Image_Url
            , TRY_CAST(practitioner_id                   AS INT)  AS Practitioner_ID
            , TRY_CAST(user_id                           AS INT)  AS User_ID
            , TRY_CAST(payment_plan_id                   AS INT)  AS Payment_Plan_ID
            , LEFT(room_id,                                255)   AS Room_ID
            , LEFT(practitioner_site_id,                    50)   AS Practitioner_Site_ID
            , LEFT(start_time,                             255)   AS Start_Time
            , LEFT(finish_time,                            255)   AS Finish_Time
            , TRY_CAST(duration                          AS INT)  AS Duration
            , LEFT(reason,                                 255)   AS Reason
            , LEFT(state,                                  255)   AS State
            , LEFT(booked_via_api,                            255)   AS Booked_Via_API
            , LEFT(pending_at,                             255)   AS Pending_At
            , LEFT(confirmed_at,                           255)   AS Confirmed_At
            , LEFT(arrived_at,                             255)   AS Arrived_At
            , LEFT(in_surgery_at,                          255)   AS In_Surgery_At
            , LEFT(completed_at,                           255)   AS Completed_At
            , LEFT(cancelled_at,                           255)   AS Cancelled_At
            , LEFT(did_not_attend_at,                      255)   AS Did_Not_Attend_At
        INTO #src
        FROM Stage.Appointments
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.UUID                               = src.UUID
            , tgt.Appointment_Cancellation_Reason_ID = src.Appointment_Cancellation_Reason_ID
            , tgt.Patient_ID                         = src.Patient_ID
            , tgt.Patient_Name                       = src.Patient_Name
            , tgt.Patient_Image_Url                  = src.Patient_Image_Url
            , tgt.Practitioner_ID                    = src.Practitioner_ID
            , tgt.User_ID                            = src.User_ID
            , tgt.Payment_Plan_ID                    = src.Payment_Plan_ID
            , tgt.Room_ID                            = src.Room_ID
            , tgt.Practitioner_Site_ID               = src.Practitioner_Site_ID
            , tgt.Start_Time                         = src.Start_Time
            , tgt.Finish_Time                        = src.Finish_Time
            , tgt.Duration                           = src.Duration
            , tgt.Reason                             = src.Reason
            , tgt.State                              = src.State
            , tgt.Booked_Via_API                     = src.Booked_Via_API
            , tgt.Pending_At                         = src.Pending_At
            , tgt.Confirmed_At                       = src.Confirmed_At
            , tgt.Arrived_At                         = src.Arrived_At
            , tgt.In_Surgery_At                      = src.In_Surgery_At
            , tgt.Completed_At                       = src.Completed_At
            , tgt.Cancelled_At                       = src.Cancelled_At
            , tgt.Did_Not_Attend_At                  = src.Did_Not_Attend_At
            , tgt.DW_Loaded_At                       = SYSUTCDATETIME()
        FROM Bronze.Appointments AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Appointments (
            Tenant_ID, ID, UUID, Appointment_Cancellation_Reason_ID,
            Patient_ID, Patient_Name, Patient_Image_Url,
            Practitioner_ID, User_ID, Payment_Plan_ID, Room_ID, Practitioner_Site_ID,
            Start_Time, Finish_Time, Duration, Reason, State,
            Booked_Via_API,
            Pending_At, Confirmed_At, Arrived_At, In_Surgery_At,
            Completed_At, Cancelled_At, Did_Not_Attend_At,
            DW_Loaded_At
        )
        SELECT
            src.Tenant_ID, src.ID, src.UUID, src.Appointment_Cancellation_Reason_ID,
            src.Patient_ID, src.Patient_Name, src.Patient_Image_Url,
            src.Practitioner_ID, src.User_ID, src.Payment_Plan_ID, src.Room_ID, src.Practitioner_Site_ID,
            src.Start_Time, src.Finish_Time, src.Duration, src.Reason, src.State,
            src.Booked_Via_API,
            src.Pending_At, src.Confirmed_At, src.Arrived_At, src.In_Surgery_At,
            src.Completed_At, src.Cancelled_At, src.Did_Not_Attend_At,
            SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Appointments tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;


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
