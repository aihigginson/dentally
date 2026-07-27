--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Patients] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Patients
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Add -1 unknown seed row; protect from DELETE
--    *03     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--    *04     19/05/2026  AIH Compute Next_Appointment_Date from Silver.Appointments (future, non-cancelled)
--    *05     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *06     22/05/2026  AIH Add Patient_Count (1 for real rows, 0 for sentinel)
--    *07     29/05/2026  AIH Add fk_Acquisition_Source snowflake FK
--    *08     14/06/2026  AIH Add Is_Email_Missing + Is_Phone_Missing
--    *09     17/06/2026  AIH DATA MINIMISATION (V011): drop special-category + excess-identifier
--                            columns (Title/Middle name, DOB/Age, Gender, Ethnicity, NHS/NI numbers,
--                            Work phone, Address, Medical Alert, Family/Custom, NHS exemption). Retain
--                            identity-for-contact (names + preferred, phone, email), contactability
--                            flags + the non-sensitive operational analytics. Full_Name now First+Last
--                            (no Title). See DPIA.md sec 7.
--    *10     18/06/2026  AIH V014: inactive patients (Active=0) are NOT flagged Is_Email/Phone_Missing
--                            (their contact is deliberately removed in V013, not actionable-missing)
--    *11     19/06/2026  AIH V015: carry contact-preference fields (Use_Email, Use_SMS, Preferred_Phone)
--                            through from Silver (active patients only; NULL for inactive per V013)
--    *12     08/07/2026  AIH V050: Lapsed_Type + fk_Date_Lapsed. Type A "Set as inactive" (Active=0,
--                            lapse date = updated_at); Type B "Calculated as inactive" (Active=1 but
--                            last appointment > 730 days ago, lapse date = last appt + 730). Disjoint
--                            by the Active flag, so a cumulative Lapsed measure = A + B (no overlap).
--    *13     22/07/2026  AIH V110: denormalise Standard_Payment_Plan onto the patient (dedup Silver
--                            plan name + Input.Payment_Plan_Map override) so patients slice by plan
--                            without a per-tenant natural-key relationship. Drives Patients-by-Plan.
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Patients @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Patients]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Patients]
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
    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
    SET NOCOUNT ON;
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        SELECT
            p.Tenant_ID                                                                             AS Tenant_ID,
            CAST(p.Patient_ID AS INT)                                                               AS Patient_ID,
            CAST(p.Account_ID AS INT)                                                               AS Account_ID,
            NULLIF(TRIM(p.First_Name), '')                                                          AS First_Name,
            NULLIF(TRIM(p.Last_Name), '')                                                           AS Last_Name,
            NULLIF(TRIM(p.Preferred_Name), '')                                                      AS Preferred_Name,
            NULLIF(CONCAT_WS(' ',
                NULLIF(TRIM(p.First_Name), ''),
                NULLIF(TRIM(p.Last_Name), '')), '')                                                 AS Full_Name,
            NULLIF(TRIM(p.Email_Address), '')                                                       AS Email_Address,
            NULLIF(TRIM(p.Home_Phone), '')                                                          AS Home_Phone,
            NULLIF(TRIM(p.Mobile_Phone), '')                                                        AS Mobile_Phone,
            -- Inactive patients have contact deliberately removed (V013), so they are NOT "missing"
            -- contact (the flag drives actionable lists for active patients) -> force 0 when inactive.
            CASE WHEN ISNULL(p.Active,0)=0 THEN 0
                 WHEN NULLIF(TRIM(p.Email_Address),'') IS NULL THEN 1 ELSE 0 END                     AS Is_Email_Missing,
            CASE WHEN ISNULL(p.Active,0)=0 THEN 0
                 WHEN NULLIF(TRIM(p.Mobile_Phone),'') IS NULL
                  AND NULLIF(TRIM(p.Home_Phone),'')   IS NULL THEN 1 ELSE 0 END                      AS Is_Phone_Missing,
            CAST(ISNULL(p.Active, 0) AS BIT)                                                        AS Active,
            CAST(p.Payment_Plan_ID AS INT)                                                          AS Payment_Plan_ID,
            -- Denormalised plan name so patients slice by plan without a (per-tenant, would-fan-out)
            -- model relationship. Same standardisation Dim_Payment_Plans uses (Input.Payment_Plan_Map
            -- override, else the raw plan name). See Patients-by-Plan on My Data.
            COALESCE(NULLIF(TRIM(m.Standard_Payment_Plan), ''),
                     LEFT(NULLIF(TRIM(spp.Payment_Plan_Name), ''), 100))                            AS Standard_Payment_Plan,
            NULLIF(TRIM(p.Site_ID), '')                                                             AS Site_ID,
            NULLIF(TRIM(p.Acquisition_Source_ID), '')                                               AS Acquisition_Source_ID,
            ISNULL(das.pk_Acquisition_Source, -1)                                                   AS fk_Acquisition_Source,
            CAST(p.Dentist_Practitioner_ID AS INT)                                                  AS Dentist_Practitioner_ID,
            CAST(p.Hygienist_Practitioner_ID AS INT)                                                AS Hygienist_Practitioner_ID,
            CAST(p.Dentist_Recall_Date AS DATE)                                                     AS Dentist_Recall_Date,
            CAST(p.Dentist_Recall_Interval AS INT)                                                  AS Dentist_Recall_Interval_Months,
            CAST(p.Hygienist_Recall_Date AS DATE)                                                   AS Hygienist_Recall_Date,
            CAST(p.Hygienist_Recall_Interval AS INT)                                                AS Hygienist_Recall_Interval_Months,
            NULLIF(TRIM(p.Recall_Method), '')                                                       AS Recall_Method,
            p.Use_Email                                                                             AS Use_Email,
            p.Use_SMS                                                                               AS Use_SMS,
            NULLIF(TRIM(p.Preferred_Phone), '')                                                     AS Preferred_Phone,
            NULLIF(p.Marketing_Opt_In, 0)                                                           AS Marketing_Consent,
            TRY_CAST(NULLIF(TRIM(ps.First_Appointment_Date), '') AS DATE)                           AS First_Appointment_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date), '') AS DATE)                            AS Last_Appointment_Date,
            next_apt.Next_Appointment_Date                                                          AS Next_Appointment_Date,
            TRY_CAST(NULLIF(TRIM(ps.First_Exam_Date), '') AS DATE)                                  AS First_Exam_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Exam_Date), '') AS DATE)                                   AS Last_Exam_Date,
            TRY_CAST(NULLIF(TRIM(ps.Next_Exam_Date), '') AS DATE)                                   AS Next_Exam_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Scale_And_Polish_Date), '') AS DATE)                       AS Last_Scale_Polish_Date,
            TRY_CAST(NULLIF(TRIM(ps.Next_Scale_And_Polish_Date), '') AS DATE)                       AS Next_Scale_Polish_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_FTA_Appointment_Date), '') AS DATE)                        AS Last_FTA_Date,
            TRY_CAST(NULLIF(TRIM(ps.Last_Cancelled_Appointment_Date), '') AS DATE)                  AS Last_Cancelled_Appointment_Date,
            CAST(ps.Total_Paid AS DECIMAL(18,4))                                                    AS Total_Paid,
            CAST(ps.Total_Invoiced AS DECIMAL(18,4))                                                AS Total_Invoiced,
            TRY_CAST(p.Created_At AS DATE)                                                          AS Patient_Created_Date,
            TRY_CAST(p.Updated_At AS DATE)                                                          AS Patient_Updated_Date,
            CAST(1 AS INT)                                                                          AS Patient_Count,
            -- Lapsed (V050): Type A "Set as inactive" (Active=0, lapse date = updated_at); Type B
            -- "Calculated as inactive" (Active, last appt > 730d ago AND no future appt booked -- a
            -- booking un-lapses them, recomputed each build; lapse date = last appt + 730). Disjoint
            -- by Active. Date -> Dim_Date (fk_Date_Lapsed) so Lapsed slices by the period it fell in.
            CASE WHEN CAST(ISNULL(p.Active,0) AS BIT) = 0 THEN 'Set as inactive'
                 WHEN TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date),'') AS DATE) <= DATEADD(DAY,-730,@Today)
                      AND next_apt.Next_Appointment_Date IS NULL THEN 'Calculated as inactive'
                 ELSE NULL END                                                                      AS Lapsed_Type,
            dd_lap.pk_Date                                                                          AS fk_Date_Lapsed
        INTO #src
        FROM Silver.Patients p
        LEFT JOIN Silver.Patient_Stats ps ON ps.Patient_ID = p.Patient_ID AND ps.Tenant_ID = p.Tenant_ID
        LEFT JOIN (
            SELECT   a.Patient_ID,
                     a.Tenant_ID,
                     MIN(TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time),''), 10) AS DATE)) AS Next_Appointment_Date
            FROM     Silver.Appointments a
            WHERE    a.Cancelled_At IS NULL
            AND      TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time),''), 10) AS DATE) > CAST(SYSUTCDATETIME() AS DATE)
            GROUP BY a.Patient_ID, a.Tenant_ID
        ) next_apt ON next_apt.Patient_ID = p.Patient_ID AND next_apt.Tenant_ID = p.Tenant_ID
        LEFT JOIN Gold.Dim_Acquisition_Sources das
            ON das.Acquisition_Source_ID = NULLIF(TRIM(p.Acquisition_Source_ID), '')
           AND das.Tenant_ID             = p.Tenant_ID
        -- Plan name for Standard_Payment_Plan. Dedup Silver by (Tenant, Payment_Plan_ID) so a
        -- multi-site plan can't fan out patient rows; then the tenant's standard-name override.
        LEFT JOIN (
            SELECT   Tenant_ID,
                     CAST(Payment_Plan_ID AS INT)          AS Payment_Plan_ID,
                     MAX(NULLIF(TRIM(Payment_Plan_Name), '')) AS Payment_Plan_Name
            FROM     Silver.Payment_Plans
            GROUP BY Tenant_ID, CAST(Payment_Plan_ID AS INT)
        ) spp ON spp.Payment_Plan_ID = CAST(p.Payment_Plan_ID AS INT)
             AND spp.Tenant_ID       = p.Tenant_ID
        LEFT JOIN Input.Payment_Plan_Map m
            ON m.Tenant_ID           = p.Tenant_ID
           AND m.Source_Payment_Plan = spp.Payment_Plan_Name
        LEFT JOIN Gold.Dim_Date dd_lap
            ON dd_lap.Full_Date =
               CASE WHEN CAST(ISNULL(p.Active,0) AS BIT) = 0 THEN TRY_CAST(p.Updated_At AS DATE)
                    WHEN TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date),'') AS DATE) <= DATEADD(DAY,-730,@Today)
                         AND next_apt.Next_Appointment_Date IS NULL
                         THEN DATEADD(DAY, 730, TRY_CAST(NULLIF(TRIM(ps.Last_Appointment_Date),'') AS DATE))
                    ELSE NULL END
        WHERE p.Patient_ID IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Patients tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Patient_ID = tgt.Patient_ID AND Tenant_ID = tgt.Tenant_ID)
        AND tgt.pk_Patient <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Account_ID                          = src.Account_ID,
            First_Name                          = src.First_Name,
            Last_Name                           = src.Last_Name,
            Preferred_Name                      = src.Preferred_Name,
            Full_Name                           = src.Full_Name,
            Email_Address                       = src.Email_Address,
            Home_Phone                          = src.Home_Phone,
            Mobile_Phone                        = src.Mobile_Phone,
            Is_Email_Missing                    = src.Is_Email_Missing,
            Is_Phone_Missing                    = src.Is_Phone_Missing,
            Active                              = src.Active,
            Payment_Plan_ID                     = src.Payment_Plan_ID,
            Standard_Payment_Plan               = src.Standard_Payment_Plan,
            Site_ID                             = src.Site_ID,
            fk_Acquisition_Source               = src.fk_Acquisition_Source,
            Dentist_Recall_Date                 = src.Dentist_Recall_Date,
            Dentist_Recall_Interval_Months      = src.Dentist_Recall_Interval_Months,
            Hygienist_Recall_Date               = src.Hygienist_Recall_Date,
            Hygienist_Recall_Interval_Months    = src.Hygienist_Recall_Interval_Months,
            Recall_Method                       = src.Recall_Method,
            Use_Email                           = src.Use_Email,
            Use_SMS                             = src.Use_SMS,
            Preferred_Phone                     = src.Preferred_Phone,
            Marketing_Consent                   = src.Marketing_Consent,
            First_Appointment_Date              = src.First_Appointment_Date,
            Last_Appointment_Date               = src.Last_Appointment_Date,
            Next_Appointment_Date               = src.Next_Appointment_Date,
            First_Exam_Date                     = src.First_Exam_Date,
            Last_Exam_Date                      = src.Last_Exam_Date,
            Next_Exam_Date                      = src.Next_Exam_Date,
            Last_Scale_Polish_Date              = src.Last_Scale_Polish_Date,
            Next_Scale_Polish_Date              = src.Next_Scale_Polish_Date,
            Last_FTA_Date                       = src.Last_FTA_Date,
            Last_Cancelled_Appointment_Date     = src.Last_Cancelled_Appointment_Date,
            Total_Paid                          = src.Total_Paid,
            Total_Invoiced                      = src.Total_Invoiced,
            Patient_Updated_Date                = src.Patient_Updated_Date,
            Lapsed_Type                         = src.Lapsed_Type,
            fk_Date_Lapsed                      = src.fk_Date_Lapsed,
            DW_Updated_At                       = SYSUTCDATETIME()
        FROM Gold.Dim_Patients tgt
        INNER JOIN #src src ON tgt.Patient_ID = src.Patient_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Account_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Preferred_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Email_Address] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Home_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Email_Missing] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Phone_Missing] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Payment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Standard_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Acquisition_Source] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Hygienist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Hygienist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Recall_Method] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Use_Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Use_SMS] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Preferred_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Marketing_Consent] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Next_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Next_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Next_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_FTA_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Cancelled_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Total_Paid] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Total_Invoiced] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Updated_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Lapsed_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Lapsed] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Account_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Preferred_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Email_Address] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Home_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Email_Missing] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Phone_Missing] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Payment_Plan_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Standard_Payment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Acquisition_Source] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Dentist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Dentist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Hygienist_Recall_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Hygienist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Recall_Method] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Use_Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Use_SMS] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Preferred_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Marketing_Consent] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Next_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Next_Exam_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Next_Scale_Polish_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_FTA_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Cancelled_Appointment_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Total_Paid] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Total_Invoiced] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Updated_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Lapsed_Type] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Lapsed] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_Patient_base BIGINT = ISNULL((SELECT MAX(pk_Patient) FROM Gold.Dim_Patients WHERE pk_Patient > 0), 0);
        INSERT INTO Gold.Dim_Patients (
            pk_Patient,
            Tenant_ID, Patient_ID, Account_ID, First_Name, Last_Name, Preferred_Name, Full_Name,
            Email_Address, Home_Phone, Mobile_Phone, Is_Email_Missing, Is_Phone_Missing,
            Active, Payment_Plan_ID, Standard_Payment_Plan, Site_ID,
            Acquisition_Source_ID, fk_Acquisition_Source, Dentist_Practitioner_ID, Hygienist_Practitioner_ID,
            Dentist_Recall_Date, Dentist_Recall_Interval_Months,
            Hygienist_Recall_Date, Hygienist_Recall_Interval_Months,
            Recall_Method, Use_Email, Use_SMS, Preferred_Phone, Marketing_Consent,
            First_Appointment_Date, Last_Appointment_Date, Next_Appointment_Date,
            First_Exam_Date, Last_Exam_Date, Next_Exam_Date,
            Last_Scale_Polish_Date, Next_Scale_Polish_Date,
            Last_FTA_Date, Last_Cancelled_Appointment_Date,
            Total_Paid, Total_Invoiced,
            Patient_Created_Date, Patient_Updated_Date, Lapsed_Type, fk_Date_Lapsed, Patient_Count, DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_Patient_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Patient_ID),
            src.Tenant_ID, src.Patient_ID, src.Account_ID, src.First_Name, src.Last_Name,
            src.Preferred_Name, src.Full_Name, src.Email_Address,
            src.Home_Phone, src.Mobile_Phone, src.Is_Email_Missing, src.Is_Phone_Missing,
            src.Active, src.Payment_Plan_ID, src.Standard_Payment_Plan, src.Site_ID,
            src.Acquisition_Source_ID, src.fk_Acquisition_Source, src.Dentist_Practitioner_ID, src.Hygienist_Practitioner_ID,
            src.Dentist_Recall_Date, src.Dentist_Recall_Interval_Months,
            src.Hygienist_Recall_Date, src.Hygienist_Recall_Interval_Months,
            src.Recall_Method, src.Use_Email, src.Use_SMS, src.Preferred_Phone, src.Marketing_Consent,
            src.First_Appointment_Date, src.Last_Appointment_Date, src.Next_Appointment_Date,
            src.First_Exam_Date, src.Last_Exam_Date, src.Next_Exam_Date,
            src.Last_Scale_Polish_Date, src.Next_Scale_Polish_Date,
            src.Last_FTA_Date, src.Last_Cancelled_Appointment_Date,
            src.Total_Paid, src.Total_Invoiced,
            src.Patient_Created_Date, src.Patient_Updated_Date, src.Lapsed_Type, src.fk_Date_Lapsed, src.Patient_Count, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Patients tgt WHERE tgt.Patient_ID = src.Patient_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_Patients (pk_Patient, Tenant_ID, Patient_ID, Patient_Count, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, -1, 0, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Patients WHERE pk_Patient = -1);
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
