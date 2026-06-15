--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Appointments] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Appointments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Wrap non-date FK lookups with ISNULL(..., -1) for unknown dimension row
--    *03     13/05/2026  AIH Add Booking, This_Visit, Next_Visit, Future_Appointment from Silver.Appointment_Journey_Attrs
--    *04     14/05/2026  AIH Fix fk_Practice_Site join to use a.Site_ID instead of a.Room_ID
--    *05     20/05/2026  AIH Column naming convention fixes (ID/_ID, API)
--    *06     21/05/2026  AIH Add fk_Cancellation_Reason surrogate key via Dim_Cancellation_Reasons
--    *07     31/05/2026  AIH Join to Silver.Appointment_Journey_Attributes (renamed from Attrs);
--                            rename This_Visit->Appointment_Reason, Next_Visit->Next_Appointment,
--                            Future_Appointment->Current_State; add Delay phase
--    *08     15/06/2026  AIH Drop Delay / Next_Appointment / Current_State -- moved to DAX (computed
--                            from the appointment self-relationship + Recalls, with a hygiene toggle).
--                            Keep Booking + Appointment_Reason (static). Table is now delta-pure.
--    *09     15/06/2026  AIH Fold the journey derivation in (#journey preamble) -- Booking +
--                            Appointment_Reason computed here; retired the separate
--                            Silver.Appointment_Journey_Attributes table/proc/pipeline step.
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Fact_Appointments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
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

        -- ── Journey attributes (folded in from the former Silver derived table) ──
        -- Booking + Appointment_Reason are STATIC, backward-looking attributes of an
        -- appointment (referral / first-visit / BBYL / online / reception, and the
        -- reason-map category). Computed here so there is no separate Silver derived
        -- table/proc/pipeline step. Booking only ever looks at the patient's PAST, so
        -- it is settled at create and never changes.
        DROP TABLE IF EXISTS #appts;
        DROP TABLE IF EXISTS #first_attended;
        DROP TABLE IF EXISTS #referrals;
        DROP TABLE IF EXISTS #journey;

        SELECT
            a.Tenant_ID, a.Appointment_ID, a.Patient_ID, a.Reason, a.Booked_Via_API,
            TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time), ''), 23) AS datetime2(3)) AS Start_DT,
            TRY_CAST(LEFT(NULLIF(TRIM(a.Completed_At), ''), 23) AS datetime2(3)) AS Completed_DT,
            TRY_CAST(LEFT(NULLIF(TRIM(a.Pending_At), ''), 23) AS datetime2(3)) AS Pending_DT
        INTO #appts
        FROM Silver.Appointments a
        WHERE a.Appointment_ID IS NOT NULL;

        SELECT Tenant_ID, Patient_ID, MIN(Appointment_ID) AS First_Appt_ID
        INTO #first_attended FROM #appts WHERE Completed_DT IS NOT NULL GROUP BY Tenant_ID, Patient_ID;

        SELECT Tenant_ID, Patient_ID, MIN(COALESCE(Created_At, DW_Created_At)) AS Earliest_Referral_DT
        INTO #referrals FROM Silver.Patient_Referrals GROUP BY Tenant_ID, Patient_ID;

        SELECT
            a.Tenant_ID,
            a.Appointment_ID,
            CASE
                WHEN ref_appt.Appointment_ID = a.Appointment_ID THEN 'Referral'
                WHEN fa.First_Appt_ID        = a.Appointment_ID THEN 'New - ' + COALESCE(iam.Standard_Acquisition_Source, aqs.Name)
                WHEN a.Booked_Via_API = 1
                     AND prev_appt.Prev_Date IS NOT NULL
                     AND CAST(a.Pending_DT AS DATE) = prev_appt.Prev_Date THEN 'BBYL'
                WHEN a.Booked_Via_API = 1                                  THEN 'Online'
                ELSE 'Reception'
            END AS Booking,
            COALESCE(arm_this.Category, NULLIF(TRIM(a.Reason), '')) AS Appointment_Reason
        INTO #journey
        FROM #appts a
        LEFT JOIN #first_attended  fa   ON fa.Tenant_ID  = a.Tenant_ID  AND fa.Patient_ID  = a.Patient_ID
        LEFT JOIN #referrals       ref  ON ref.Tenant_ID = a.Tenant_ID  AND ref.Patient_ID = a.Patient_ID
        LEFT JOIN Silver.Patients  pat  ON pat.Tenant_ID = a.Tenant_ID  AND pat.Patient_ID = a.Patient_ID
        LEFT JOIN Silver.Acquisition_Sources     aqs ON aqs.Tenant_ID = pat.Tenant_ID AND aqs.Acquisition_Source_ID = pat.Acquisition_Source_ID
        LEFT JOIN Input.Acquisition_Source_Map  iam ON iam.Tenant_ID = pat.Tenant_ID AND iam.Source_Acquisition_Source = aqs.Name
        LEFT JOIN Silver.Appointment_Reason_Map arm_this ON arm_this.Reason_Text = NULLIF(TRIM(a.Reason), '')
        OUTER APPLY (
            SELECT TOP 1 CAST(pa.Start_DT AS DATE) AS Prev_Date
            FROM #appts pa
            WHERE pa.Tenant_ID = a.Tenant_ID AND pa.Patient_ID = a.Patient_ID
              AND pa.Completed_DT IS NOT NULL AND pa.Start_DT < a.Start_DT
            ORDER BY pa.Start_DT DESC, pa.Appointment_ID DESC
        ) prev_appt
        OUTER APPLY (
            SELECT TOP 1 ra.Appointment_ID
            FROM #appts ra
            WHERE ref.Earliest_Referral_DT IS NOT NULL
              AND ra.Tenant_ID = a.Tenant_ID AND ra.Patient_ID = a.Patient_ID
              AND ra.Start_DT >= ref.Earliest_Referral_DT
            ORDER BY ra.Start_DT, ra.Appointment_ID
        ) ref_appt;

        DROP TABLE IF EXISTS #appts;
        DROP TABLE IF EXISTS #first_attended;
        DROP TABLE IF EXISTS #referrals;

        SELECT
            a.Tenant_ID                                                 AS Tenant_ID,
            CAST(a.Appointment_ID AS INT)                               AS bk_Appointment_ID,

            ISNULL(dpat.pk_Patient, -1)                                 AS fk_Patient,
            ISNULL(dpr.pk_Practitioner, -1)                             AS fk_Practitioner,
            ISNULL(dpp.pk_Payment_Plan, -1)                             AS fk_Payment_Plan,
            ISNULL(dps.pk_Practice_Site, -1)                            AS fk_Practice_Site,
            ISNULL(du.pk_User, -1)                                      AS fk_User,
            ISNULL(dcr.pk_Cancellation_Reason, -1)                      AS fk_Cancellation_Reason,

            dd_s.pk_Date                                                AS fk_Date_Start,
            dd_p.pk_Date                                                AS fk_Date_Pending,
            dd_c.pk_Date                                                AS fk_Date_Created,

            NULLIF(TRIM(a.Room_ID),'')                                  AS Room_ID,
            NULLIF(TRIM(a.State),'')                                    AS State,
            NULLIF(TRIM(a.Reason),'')                                   AS Reason,
            NULLIF(TRIM(a.Treatment_Description),'')                    AS Treatment_Description,
            NULLIF(TRIM(a.Notes),'')                                    AS Notes,
            a.Appointment_Cancellation_Reason_ID                        AS Cancellation_Reason_ID,

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
            END                                                         AS In_Surgery_Mins,

            ja.Booking                                                  AS Booking,
            ja.Appointment_Reason                                       AS Appointment_Reason
        INTO #src
        FROM Silver.Appointments a
        LEFT JOIN Gold.Dim_Patients dpat        ON dpat.Patient_ID      = a.Patient_ID          AND dpat.Tenant_ID = a.Tenant_ID
        LEFT JOIN Gold.Dim_Practitioners dpr    ON dpr.Practitioner_ID  = CAST(a.Practitioner_ID AS INT) AND dpr.Tenant_ID = a.Tenant_ID
        LEFT JOIN Gold.Dim_Payment_Plans dpp    ON dpp.Payment_Plan_ID  = CAST(a.Payment_Plan_ID AS INT) AND dpp.Tenant_ID = a.Tenant_ID
        LEFT JOIN Gold.Dim_Practice_Sites dps   ON dps.Site_ID          = NULLIF(TRIM(a.Site_ID),'') AND dps.Tenant_ID = a.Tenant_ID
        LEFT JOIN Gold.Dim_Users du             ON du.bk_User_ID        = CAST(a.User_ID AS INT) AND du.Tenant_ID = a.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_s            ON dd_s.Full_Date       = CAST(a.Start_Time AS DATE)
        LEFT JOIN Gold.Dim_Date dd_p            ON dd_p.Full_Date       = CAST(a.Pending_At AS DATE)
        LEFT JOIN Gold.Dim_Date dd_c            ON dd_c.Full_Date       = CAST(a.Created_At AS DATE)
        LEFT JOIN Gold.Dim_Cancellation_Reasons dcr ON dcr.bk_Cancellation_Reason_ID = NULLIF(TRIM(a.Appointment_Cancellation_Reason_ID),'') AND dcr.Tenant_ID = a.Tenant_ID
        LEFT JOIN #journey ja                   ON ja.Appointment_ID   = a.Appointment_ID AND ja.Tenant_ID = a.Tenant_ID
        WHERE a.Appointment_ID IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Appointments tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Appointment_ID = tgt.bk_Appointment_ID AND Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Patient              = src.fk_Patient,
            fk_Practitioner         = src.fk_Practitioner,
            fk_Payment_Plan         = src.fk_Payment_Plan,
            fk_Practice_Site        = src.fk_Practice_Site,
            fk_User                 = src.fk_User,
            fk_Cancellation_Reason  = src.fk_Cancellation_Reason,
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
            Booking                 = src.Booking,
            Appointment_Reason      = src.Appointment_Reason,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Fact_Appointments tgt
        INNER JOIN #src src ON tgt.bk_Appointment_ID = src.bk_Appointment_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_User] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Cancellation_Reason] AS VARCHAR(500)), ''),
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
           ISNULL(CAST(tgt.[In_Surgery_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Booking] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Appointment_Reason] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_User] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Cancellation_Reason] AS VARCHAR(500)), ''),
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
           ISNULL(CAST(src.[In_Surgery_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Booking] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Appointment_Reason] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Appointments (
            Tenant_ID,
            bk_Appointment_ID,
            fk_Patient, fk_Practitioner, fk_Payment_Plan, fk_Practice_Site, fk_User, fk_Cancellation_Reason,
            fk_Date_Start, fk_Date_Pending, fk_Date_Created,
            Room_ID, State, Reason, Treatment_Description, Notes, Cancellation_Reason_ID,
            Arrived_At, In_Surgery_At, Completed_At, Confirmed_At, Cancelled_At, Did_Not_Attend_At,
            Start_Time, Finish_Time, Pending_At,
            Is_Completed, Is_Cancelled, Is_DNA, Is_Arrived,
            Duration_Mins, Waiting_Mins, In_Surgery_Mins,
            Booking, Appointment_Reason,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID,
            src.bk_Appointment_ID,
            src.fk_Patient, src.fk_Practitioner, src.fk_Payment_Plan, src.fk_Practice_Site, src.fk_User, src.fk_Cancellation_Reason,
            src.fk_Date_Start, src.fk_Date_Pending, src.fk_Date_Created,
            src.Room_ID, src.State, src.Reason, src.Treatment_Description, src.Notes, src.Cancellation_Reason_ID,
            src.Arrived_At, src.In_Surgery_At, src.Completed_At, src.Confirmed_At, src.Cancelled_At, src.Did_Not_Attend_At,
            src.Start_Time, src.Finish_Time, src.Pending_At,
            src.Is_Completed, src.Is_Cancelled, src.Is_DNA, src.Is_Arrived,
            src.Duration_Mins, src.Waiting_Mins, src.In_Surgery_Mins,
            src.Booking, src.Appointment_Reason,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Appointments tgt WHERE tgt.bk_Appointment_ID = src.bk_Appointment_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
        DROP TABLE IF EXISTS #journey;
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
