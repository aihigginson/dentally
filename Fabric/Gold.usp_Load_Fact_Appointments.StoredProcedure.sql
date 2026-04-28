/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Appointments]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Appointments]
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
            CAST(a.Appointment_Id AS INT)                               AS bk_Appointment_ID,

            dpat.pk_Patient                                             AS fk_Patient,
            dpr.pk_Practitioner                                         AS fk_Practitioner,
            dpp.pk_Payment_Plan                                         AS fk_Payment_Plan,
            dps.pk_Practice_Site                                        AS fk_Practice_Site,
            du.pk_User                                                  AS fk_User,

            dd_s.pk_Date                                                AS fk_Date_Start,
            dd_p.pk_Date                                                AS fk_Date_Pending,
            dd_c.pk_Date                                                AS fk_Date_Created,

            NULLIF(TRIM(a.Room_Id),'')                                  AS Room_ID,
            NULLIF(TRIM(a.State),'')                                    AS State,
            NULLIF(TRIM(a.Reason),'')                                   AS Reason,
            NULLIF(TRIM(a.Treatment_Description),'')                    AS Treatment_Description,
            NULLIF(TRIM(a.Notes),'')                                    AS Notes,
            a.Appointment_Cancellation_Reason_Id                        AS Cancellation_Reason_ID,

            TRY_CAST(NULLIF(TRIM(a.Arrived_At),'') AS datetime2(3))         AS Arrived_At,
            TRY_CAST(NULLIF(TRIM(a.In_Surgery_At),'') AS datetime2(3))      AS In_Surgery_At,
            TRY_CAST(NULLIF(TRIM(a.Completed_At),'') AS datetime2(3))       AS Completed_At,
            TRY_CAST(NULLIF(TRIM(a.Confirmed_At),'') AS datetime2(3))       AS Confirmed_At,
            TRY_CAST(NULLIF(TRIM(a.Cancelled_At),'') AS datetime2(3))       AS Cancelled_At,
            TRY_CAST(NULLIF(TRIM(a.Did_Not_Attend_At),'') AS datetime2(3))  AS Did_Not_Attend_At,

            TRY_CAST(NULLIF(TRIM(a.Start_Time),'') AS datetime2(3))         AS Start_Time,
            TRY_CAST(NULLIF(TRIM(a.Finish_Time),'') AS datetime2(3))        AS Finish_Time,
            TRY_CAST(NULLIF(TRIM(a.Pending_At),'') AS datetime2(3))         AS Pending_At,

            CASE WHEN a.Completed_At IS NOT NULL THEN 1 ELSE 0 END      AS Is_Completed,
            CASE WHEN a.Cancelled_At IS NOT NULL THEN 1 ELSE 0 END      AS Is_Cancelled,
            CASE WHEN a.Did_Not_Attend_At IS NOT NULL THEN 1 ELSE 0 END AS Is_DNA,
            CASE WHEN a.Arrived_At IS NOT NULL THEN 1 ELSE 0 END        AS Is_Arrived,

            CAST(ISNULL(a.Duration,0) AS INT)                           AS Duration_Mins,

            CASE WHEN a.Arrived_At IS NOT NULL AND a.In_Surgery_At IS NOT NULL
                 THEN DATEDIFF(MINUTE,
                        TRY_CAST(NULLIF(TRIM(a.Arrived_At),'') AS datetime2(3)),
                        TRY_CAST(NULLIF(TRIM(a.In_Surgery_At),'') AS datetime2(3)))
            END                                                         AS Waiting_Mins,

            CASE WHEN a.In_Surgery_At IS NOT NULL AND a.Completed_At IS NOT NULL
                 THEN DATEDIFF(MINUTE,
                        TRY_CAST(NULLIF(TRIM(a.In_Surgery_At),'') AS datetime2(3)),
                        TRY_CAST(NULLIF(TRIM(a.Completed_At),'') AS datetime2(3)))
            END                                                         AS In_Surgery_Mins
        INTO #src
        FROM Silver.Appointments a
        LEFT JOIN Gold.Dim_Patients dpat        ON dpat.Patient_ID      = a.Patient_Id
        LEFT JOIN Gold.Dim_Practitioners dpr    ON dpr.Practitioner_ID  = CAST(a.Practitioner_Id AS INT)
        LEFT JOIN Gold.Dim_Payment_Plans dpp    ON dpp.Payment_Plan_ID  = CAST(a.Payment_Plan_Id AS INT)
        LEFT JOIN Gold.Dim_Practice_Sites dps   ON dps.Site_ID          = NULLIF(TRIM(a.Room_Id),'')
        LEFT JOIN Gold.Dim_Users du             ON du.bk_User_ID        = CAST(a.User_Id AS INT)
        LEFT JOIN Gold.Dim_Date dd_s            ON dd_s.Full_Date       = CAST(a.Start_Time AS DATE)
        LEFT JOIN Gold.Dim_Date dd_p            ON dd_p.Full_Date       = CAST(a.Pending_At AS DATE)
        LEFT JOIN Gold.Dim_Date dd_c            ON dd_c.Full_Date       = CAST(a.Created_At AS DATE)
        WHERE a.Appointment_Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Appointments tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Appointment_ID = tgt.bk_Appointment_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Patient              = src.fk_Patient,
            fk_Practitioner         = src.fk_Practitioner,
            fk_Payment_Plan         = src.fk_Payment_Plan,
            fk_Practice_Site        = src.fk_Practice_Site,
            fk_User                 = src.fk_User,
            fk_Date_Start           = src.fk_Date_Start,
            fk_Date_Pending         = src.fk_Date_Pending,
            fk_Date_Created         = src.fk_Date_Created,
            Room_ID                 = src.Room_ID,
            State                   = src.State,
            Reason                  = src.Reason,
            Treatment_Description   = src.Treatment_Description,
            Notes                   = src.Notes,
            Cancellation_Reason_ID  = src.Cancellation_Reason_ID,
            Arrived_At              = src.Arrived_At,
            In_Surgery_At           = src.In_Surgery_At,
            Completed_At            = src.Completed_At,
            Confirmed_At            = src.Confirmed_At,
            Cancelled_At            = src.Cancelled_At,
            Did_Not_Attend_At       = src.Did_Not_Attend_At,
            Start_Time              = src.Start_Time,
            Finish_Time             = src.Finish_Time,
            Pending_At              = src.Pending_At,
            Is_Completed            = src.Is_Completed,
            Is_Cancelled            = src.Is_Cancelled,
            Is_DNA                  = src.Is_DNA,
            Is_Arrived              = src.Is_Arrived,
            Duration_Mins           = src.Duration_Mins,
            Waiting_Mins            = src.Waiting_Mins,
            In_Surgery_Mins         = src.In_Surgery_Mins,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Fact_Appointments tgt
        INNER JOIN #src src ON tgt.bk_Appointment_ID = src.bk_Appointment_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_User] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Start] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Pending] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Room_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[State] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Reason] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Cancellation_Reason_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Arrived_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[In_Surgery_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Completed_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Confirmed_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Cancelled_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Did_Not_Attend_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Start_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Finish_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Pending_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Cancelled] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_DNA] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Arrived] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Waiting_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[In_Surgery_Mins] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_User] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Start] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Pending] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Created] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Room_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[State] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Reason] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Cancellation_Reason_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Arrived_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[In_Surgery_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Completed_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Confirmed_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Cancelled_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Did_Not_Attend_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Start_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Finish_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Pending_At] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Cancelled] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_DNA] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Arrived] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Waiting_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[In_Surgery_Mins] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Appointments (
            bk_Appointment_ID,
            fk_Patient, fk_Practitioner, fk_Payment_Plan, fk_Practice_Site, fk_User,
            fk_Date_Start, fk_Date_Pending, fk_Date_Created,
            Room_ID, State, Reason, Treatment_Description, Notes, Cancellation_Reason_ID,
            Arrived_At, In_Surgery_At, Completed_At, Confirmed_At, Cancelled_At, Did_Not_Attend_At,
            Start_Time, Finish_Time, Pending_At,
            Is_Completed, Is_Cancelled, Is_DNA, Is_Arrived,
            Duration_Mins, Waiting_Mins, In_Surgery_Mins,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.bk_Appointment_ID,
            src.fk_Patient, src.fk_Practitioner, src.fk_Payment_Plan, src.fk_Practice_Site, src.fk_User,
            src.fk_Date_Start, src.fk_Date_Pending, src.fk_Date_Created,
            src.Room_ID, src.State, src.Reason, src.Treatment_Description, src.Notes, src.Cancellation_Reason_ID,
            src.Arrived_At, src.In_Surgery_At, src.Completed_At, src.Confirmed_At, src.Cancelled_At, src.Did_Not_Attend_At,
            src.Start_Time, src.Finish_Time, src.Pending_At,
            src.Is_Completed, src.Is_Cancelled, src.Is_DNA, src.Is_Arrived,
            src.Duration_Mins, src.Waiting_Mins, src.In_Surgery_Mins,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Appointments tgt WHERE tgt.bk_Appointment_ID = src.bk_Appointment_ID);
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
