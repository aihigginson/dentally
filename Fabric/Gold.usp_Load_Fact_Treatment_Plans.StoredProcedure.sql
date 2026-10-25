--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Treatment_Plans] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Treatment_Plans
--  Author           :  AIH
--  Initital Date    :  21/06/2026
--  History          :
--    *01     21/06/2026  AIH Initial Release. Plan-grain fact so plan measures slice by the
--                            PLAN's own practitioner/site/date (not its items'). Resolves
--                            fk_Patient/Practitioner/Practice_Site/Treatment_Plan + fk_Date_*
--                            from Silver.Treatment_Plans. Delete-orphans / hash-update /
--                            insert-new upsert (no watermark; processes all Silver, like the dim).
--    *02     13/07/2026  AIH Item value split used tpi.Total_Price (NULL on real Dentally data -- a
--                            mock-era field); real line value is tpi.Price. Completed/Outstanding
--                            private value were £0 -> Open Courses (Without Appt) Value blank. Now
--                            ISNULL(TRY_CAST(tpi.Price AS DECIMAL(18,4)),0).
--  To Run			 :   DECLARE  @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_Treatment_Plans @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Treatment_Plans]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Treatment_Plans]
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

        -- Resolve the plan's OWN dimension keys (practitioner / site / patient / dates) so the
        -- plan-grain measures slice correctly. -1 = unknown (FK guard convention); dates stay
        -- NULL when unparseable (consistent with the other Gold facts).
        -- ==> WHEN DID THIS CLINICIAN FIRST SEE THIS PATIENT. <== (V229) Per patient AND per
        -- practitioner, because front-loading is a property of a RELATIONSHIP, not of the
        -- patient's first ever appointment: someone who transfers after ten years gets a
        -- first-meeting plan from their new dentist too.
        --
        -- Read from Silver, and on State = 'Completed' rather than Completed_At -- at the
        -- live practice 1,004 cancelled appointments carry a Completed_At, and a cancelled
        -- appointment is not a meeting.
        DROP TABLE IF EXISTS #met;
        SELECT a.Tenant_ID,
               CAST(a.Patient_ID AS INT)      AS Patient_ID,
               CAST(a.Practitioner_ID AS INT) AS Practitioner_ID,
               MIN(TRY_CAST(LEFT(NULLIF(TRIM(a.Start_Time), ''), 10) AS DATE)) AS First_Met_Date
        INTO   #met
        FROM   Silver.Appointments a
        WHERE  a.State = 'Completed'
          AND  a.Patient_ID IS NOT NULL
          AND  a.Practitioner_ID IS NOT NULL
        GROUP BY a.Tenant_ID, CAST(a.Patient_ID AS INT), CAST(a.Practitioner_ID AS INT);

        SELECT
            tp.Tenant_ID                                                        AS Tenant_ID,
            CAST(tp.Id AS INT)                                                  AS bk_Treatment_Plan_ID,
            ISNULL(dtp.pk_Treatment_Plan, -1)                                   AS fk_Treatment_Plan,
            ISNULL(dpat.pk_Patient, -1)                                         AS fk_Patient,
            ISNULL(dpr.pk_Practitioner, -1)                                     AS fk_Practitioner,
            -- *05 Was hardcoded -1 because Silver.Treatment_Plans.Site_ID is empty at source
            --     (blank on 44,267 demo and 71,086 live rows alike). Resolved from the
            --     practitioner instead, so plan-grain metrics survive a site selection.
            ISNULL(dps.pk_Practice_Site, -1)                                    AS fk_Practice_Site,  -- Dentally treatment-plan object has NO site -> always unknown (-1)
            dd_c.pk_Date                                                        AS fk_Date_Created,
            dd_s.pk_Date                                                        AS fk_Date_Start,
            dd_comp.pk_Date                                                     AS fk_Date_Completed,
            CAST(ISNULL(tp.Completed,0) AS BIT)                                 AS Completed,
            TRY_CAST(LEFT(NULLIF(TRIM(tp.Start_Date), ''), 10) AS DATE)         AS Start_Date,
            CAST(1 AS INT)                                                      AS Treatment_Plan_Count,
            CAST(ISNULL(tp.NHS_UDA_Value,0) AS DECIMAL(18,4))                   AS NHS_UDA_Value,
            CAST(ISNULL(tp.NHS_Completed_UDA_Value,0) AS DECIMAL(18,4))         AS NHS_Completed_UDA_Value,
            CAST(ISNULL(tp.Private_Treatment_Value,0) AS DECIMAL(18,4))         AS Private_Treatment_Value,
            -- Item roll-up (private-only value split + course lifecycle). itm/fap are LEFT joins so
            -- item-less plans still land (flags -> 0, values -> 0, status 'No Items').
            CAST(ISNULL(itm.Private_Treatment_Value_Completed,0)   AS DECIMAL(18,4)) AS Private_Treatment_Value_Completed,
            CAST(ISNULL(itm.Private_Treatment_Value_Outstanding,0) AS DECIMAL(18,4)) AS Private_Treatment_Value_Outstanding,
            itm.Last_Activity_Date                                              AS Last_Activity_Date,
            CAST(ISNULL(itm.Has_Completed_Item,0) AS BIT)                       AS Has_Completed_Item,
            CAST(ISNULL(itm.Has_Open_Item,0)      AS BIT)                       AS Has_Open_Item,
            CAST(CASE WHEN fap.Treatment_Plan_ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS Has_Future_Appointment,
            -- Course lifecycle. A completed plan implies all items done (user rule); otherwise derive
            -- from item flags. 'Open - No Appointment' = the leaky bucket (started, unfinished, no
            -- future booking). Recency is read separately off Last_Activity_Date in the report.
            CAST(CASE
                WHEN ISNULL(tp.Completed,0) = 1                                              THEN 'Complete'
                WHEN ISNULL(itm.Has_Completed_Item,0) = 1 AND ISNULL(itm.Has_Open_Item,0) = 0 THEN 'Effectively Complete'
                WHEN ISNULL(itm.Has_Completed_Item,0) = 0 AND ISNULL(itm.Has_Open_Item,0) = 1 THEN 'Proposed'
                -- *03 A would-be-OPEN plan (started + unfinished) must NOT count as an open course when it has
                --     NO outstanding private value OR the patient is INACTIVE. Reclassify so every Open Courses
                --     measure + report drops it (they filter Course_Status IN 'In Progress'/'Open - No Appointment').
                WHEN ISNULL(itm.Has_Completed_Item,0) = 1 AND ISNULL(itm.Has_Open_Item,0) = 1
                     AND (ISNULL(itm.Private_Treatment_Value_Outstanding,0) <= 0 OR ISNULL(dpat.Active,0) = 0) THEN 'Closed - Excluded'
                WHEN ISNULL(itm.Has_Completed_Item,0) = 1 AND ISNULL(itm.Has_Open_Item,0) = 1
                     AND fap.Treatment_Plan_ID IS NOT NULL                                   THEN 'In Progress'
                WHEN ISNULL(itm.Has_Completed_Item,0) = 1 AND ISNULL(itm.Has_Open_Item,0) = 1 THEN 'Open - No Appointment'
                ELSE 'No Items'
            END AS VARCHAR(40))                                                 AS Course_Status,
            -- V229. A plan written on the very day this clinician first saw this patient.
            CAST(CASE WHEN met.First_Met_Date IS NOT NULL
                       AND met.First_Met_Date = TRY_CAST(LEFT(NULLIF(TRIM(tp.Created_At), ''), 10) AS DATE)
                      THEN 1 ELSE 0 END AS BIT)                             AS Is_First_Visit_Plan,
            met.First_Met_Date                                              AS First_Met_Date,
            -- Within twelve months of this clinician first seeing them. A first-visit plan
            -- is always a first-year plan, so the share is bounded 0-1 by construction.
            CAST(CASE WHEN met.First_Met_Date IS NOT NULL
                       AND TRY_CAST(LEFT(NULLIF(TRIM(tp.Created_At), ''), 10) AS DATE)
                           < DATEADD(MONTH, 12, met.First_Met_Date)
                      THEN 1 ELSE 0 END AS BIT)                             AS Is_First_Year_Plan,
            -- Zero-value plans get their own band rather than falling into the lowest one.
            -- NHS-only courses and single-line pricing put a lot of 0.00 rows in, and letting
            -- them sit in "Under 250" drags every median and share toward nothing.
            -- ==> pv.Value, NOT tp.Private_Treatment_Value. <== The Silver column is
            -- VARCHAR(50): comparing it to an integer literal forces a varchar -> int
            -- conversion and T-SQL cannot parse '131.0000' as an int. See the CROSS APPLY.
            CAST(CASE
                WHEN pv.Value <=    0                              THEN 'No Private Value'
                WHEN pv.Value <  250                               THEN 'Under 250'
                WHEN pv.Value <  500                               THEN '250-499'
                WHEN pv.Value < 1000                               THEN '500-999'
                WHEN pv.Value < 2500                               THEN '1,000-2,499'
                ELSE                                                    '2,500+'
            END AS VARCHAR(20))                                             AS Plan_Value_Band,
            CAST(CASE
                WHEN pv.Value <=    0                              THEN 0
                WHEN pv.Value <  250                               THEN 1
                WHEN pv.Value <  500                               THEN 2
                WHEN pv.Value < 1000                               THEN 3
                WHEN pv.Value < 2500                               THEN 4
                ELSE                                                    5
            END AS INT)                                                     AS Plan_Value_Band_Sort,
            -- V231. Precedence is WHAT WAS CHARGED, not what the patient is: private value
            -- means the patient paid, whatever plan or exemption also applied to them.
            -- ==> EXISTS, NOT A JOIN. <== Input.Plan_Capitation_Rate holds one row per
            -- effective date per plan, so joining it would multiply the fact out.
            -- NHS_UDA_Value is VARCHAR(50) in Silver like the private value, so it needs
            -- parsing before it can be compared to a number.
            CAST(CASE
                WHEN pv.Value > 0                                                THEN 3
                WHEN ISNULL(TRY_CAST(tp.NHS_UDA_Value AS DECIMAL(18,4)), 0) > 0  THEN 1
                WHEN EXISTS (SELECT 1 FROM Input.Plan_Capitation_Rate cap
                             WHERE cap.Tenant_ID       = tp.Tenant_ID
                               AND cap.Payment_Plan_ID = dpat.Payment_Plan_ID)   THEN 2
                ELSE                                                                  4
            END AS INT)                                                     AS fk_Plan_Payer
        INTO #src
        FROM Silver.Treatment_Plans tp
        LEFT JOIN Gold.Dim_Treatment_Plans dtp ON dtp.Treatment_Plan_ID = CAST(tp.Id AS INT)             AND dtp.Tenant_ID = tp.Tenant_ID
        LEFT JOIN Gold.Dim_Patients dpat       ON dpat.Patient_ID       = CAST(tp.Patient_ID AS INT)     AND dpat.Tenant_ID = tp.Tenant_ID
        LEFT JOIN Gold.Dim_Practitioners dpr   ON dpr.Practitioner_ID   = CAST(tp.Practitioner_ID AS INT) AND dpr.Tenant_ID = tp.Tenant_ID
        LEFT JOIN Gold.Dim_Practice_Sites dps  ON dps.Site_ID           = dpr.Site_ID                 AND dps.Tenant_ID = tp.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_c           ON dd_c.Full_Date        = TRY_CAST(LEFT(NULLIF(TRIM(tp.Created_At),  ''),10) AS DATE)
        LEFT JOIN Gold.Dim_Date dd_s           ON dd_s.Full_Date        = TRY_CAST(LEFT(NULLIF(TRIM(tp.Start_Date),  ''),10) AS DATE)
        LEFT JOIN Gold.Dim_Date dd_comp        ON dd_comp.Full_Date     = TRY_CAST(LEFT(NULLIF(TRIM(tp.Completed_At),''),10) AS DATE)
        -- The plan value, parsed once. TRY_CAST rather than CAST: a non-numeric value is a
        -- Silver data problem and belongs in the No Private Value band, not in an exception
        -- that stops the whole warehouse load.
        CROSS APPLY (SELECT ISNULL(TRY_CAST(tp.Private_Treatment_Value AS DECIMAL(18,4)), 0)
                            AS Value) pv
        LEFT JOIN #met met                     ON met.Patient_ID        = CAST(tp.Patient_ID AS INT)
                                              AND met.Practitioner_ID   = CAST(tp.Practitioner_ID AS INT)
                                              AND met.Tenant_ID         = tp.Tenant_ID
        -- Item aggregate: has-done / has-open flags, last completed-item date (pushed up), and the
        -- private (NHS_Charge=0) value split completed-vs-outstanding. Completed is INT 0/1.
        LEFT JOIN (
            SELECT
                tpi.Tenant_ID,
                tpi.Treatment_Plan_ID,
                MAX(CASE WHEN tpi.Completed = 1 THEN 1 ELSE 0 END)                           AS Has_Completed_Item,
                MAX(CASE WHEN ISNULL(tpi.Completed,0) = 0 THEN 1 ELSE 0 END)                 AS Has_Open_Item,
                MAX(CASE WHEN tpi.Completed = 1 THEN TRY_CAST(tpi.Completed_At AS DATE) END) AS Last_Activity_Date,
                SUM(CASE WHEN tpi.Completed = 1 AND ISNULL(tpi.NHS_Charge,0) = 0
                         THEN ISNULL(TRY_CAST(tpi.Price AS DECIMAL(18,4)),0) ELSE 0 END)                          AS Private_Treatment_Value_Completed,
                SUM(CASE WHEN ISNULL(tpi.Completed,0) = 0 AND ISNULL(tpi.NHS_Charge,0) = 0
                         THEN ISNULL(TRY_CAST(tpi.Price AS DECIMAL(18,4)),0) ELSE 0 END)                          AS Private_Treatment_Value_Outstanding
            FROM Silver.Treatment_Plan_Items tpi
            GROUP BY tpi.Tenant_ID, tpi.Treatment_Plan_ID
        ) itm ON itm.Treatment_Plan_ID = CAST(tp.Id AS INT) AND itm.Tenant_ID = tp.Tenant_ID
        -- Future appointment: plan has a non-cancelled appointment dated today or later.
        LEFT JOIN (
            SELECT DISTINCT ta.Tenant_ID, ta.Treatment_Plan_ID
            FROM Silver.Treatment_Appointments ta
            INNER JOIN Silver.Appointments a ON a.Appointment_ID = ta.Appointment_ID AND a.Tenant_ID = ta.Tenant_ID
            WHERE TRY_CAST(a.Start_Time AS DATE) >= CAST(SYSUTCDATETIME() AS DATE)
              AND NULLIF(TRIM(a.Cancelled_At), '') IS NULL
        ) fap ON fap.Treatment_Plan_ID = CAST(tp.Id AS INT) AND fap.Tenant_ID = tp.Tenant_ID
        WHERE tp.Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Treatment_Plans tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src s WHERE s.bk_Treatment_Plan_ID = tgt.bk_Treatment_Plan_ID AND s.Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Treatment_Plan       = src.fk_Treatment_Plan,
            fk_Patient              = src.fk_Patient,
            fk_Practitioner         = src.fk_Practitioner,
            fk_Practice_Site        = src.fk_Practice_Site,
            fk_Date_Created         = src.fk_Date_Created,
            fk_Date_Start           = src.fk_Date_Start,
            fk_Date_Completed       = src.fk_Date_Completed,
            Completed               = src.Completed,
            Start_Date              = src.Start_Date,
            NHS_UDA_Value           = src.NHS_UDA_Value,
            NHS_Completed_UDA_Value = src.NHS_Completed_UDA_Value,
            Private_Treatment_Value = src.Private_Treatment_Value,
            Private_Treatment_Value_Completed   = src.Private_Treatment_Value_Completed,
            Private_Treatment_Value_Outstanding = src.Private_Treatment_Value_Outstanding,
            Last_Activity_Date       = src.Last_Activity_Date,
            Has_Completed_Item       = src.Has_Completed_Item,
            Has_Open_Item            = src.Has_Open_Item,
            Has_Future_Appointment   = src.Has_Future_Appointment,
            Course_Status            = src.Course_Status,
            Is_First_Visit_Plan     = src.Is_First_Visit_Plan,
            First_Met_Date          = src.First_Met_Date,
            Is_First_Year_Plan      = src.Is_First_Year_Plan,
            Plan_Value_Band         = src.Plan_Value_Band,
            Plan_Value_Band_Sort    = src.Plan_Value_Band_Sort,
            fk_Plan_Payer           = src.fk_Plan_Payer,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Fact_Treatment_Plans tgt
        INNER JOIN #src src ON tgt.bk_Treatment_Plan_ID = src.bk_Treatment_Plan_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Treatment_Plan]       AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Patient]              AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practitioner]         AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practice_Site]        AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Created]         AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Start]           AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Completed]       AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Completed]               AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Start_Date]              AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_UDA_Value]           AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Completed_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Private_Treatment_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Private_Treatment_Value_Completed]   AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Private_Treatment_Value_Outstanding] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Activity_Date]      AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Has_Completed_Item]      AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Has_Open_Item]           AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Has_Future_Appointment]  AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Course_Status]           AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_First_Visit_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Met_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_First_Year_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Plan_Value_Band] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Plan_Value_Band_Sort] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Plan_Payer] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Treatment_Plan]       AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Patient]              AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practitioner]         AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practice_Site]        AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Created]         AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Start]           AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Completed]       AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Completed]               AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Start_Date]              AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_UDA_Value]           AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Completed_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Private_Treatment_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Private_Treatment_Value_Completed]   AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Private_Treatment_Value_Outstanding] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Activity_Date]      AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Has_Completed_Item]      AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Has_Open_Item]           AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Has_Future_Appointment]  AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Course_Status]           AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_First_Visit_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Met_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_First_Year_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Plan_Value_Band] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Plan_Value_Band_Sort] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Plan_Payer] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows (pk_Treatment_Plan_Fact is IDENTITY)
        INSERT INTO Gold.Fact_Treatment_Plans (
            Tenant_ID, bk_Treatment_Plan_ID, fk_Treatment_Plan,
            fk_Patient, fk_Practitioner, fk_Practice_Site,
            fk_Date_Created, fk_Date_Start, fk_Date_Completed,
            Completed, Start_Date, Treatment_Plan_Count,
            NHS_UDA_Value, NHS_Completed_UDA_Value, Private_Treatment_Value,
            Private_Treatment_Value_Completed, Private_Treatment_Value_Outstanding,
            Last_Activity_Date, Has_Completed_Item, Has_Open_Item, Has_Future_Appointment, Course_Status,
            Is_First_Visit_Plan, First_Met_Date, Is_First_Year_Plan, Plan_Value_Band, Plan_Value_Band_Sort,
            fk_Plan_Payer,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID, src.bk_Treatment_Plan_ID, src.fk_Treatment_Plan,
            src.fk_Patient, src.fk_Practitioner, src.fk_Practice_Site,
            src.fk_Date_Created, src.fk_Date_Start, src.fk_Date_Completed,
            src.Completed, src.Start_Date, src.Treatment_Plan_Count,
            src.NHS_UDA_Value, src.NHS_Completed_UDA_Value, src.Private_Treatment_Value,
            src.Private_Treatment_Value_Completed, src.Private_Treatment_Value_Outstanding,
            src.Last_Activity_Date, src.Has_Completed_Item, src.Has_Open_Item, src.Has_Future_Appointment, src.Course_Status,
            src.Is_First_Visit_Plan, src.First_Met_Date, src.Is_First_Year_Plan, src.Plan_Value_Band, src.Plan_Value_Band_Sort,
            src.fk_Plan_Payer,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Treatment_Plans tgt WHERE tgt.bk_Treatment_Plan_ID = src.bk_Treatment_Plan_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
        DROP TABLE #met;
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
