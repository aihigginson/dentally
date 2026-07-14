--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Patient_At_Risk] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Patient_At_Risk
--  Author           :  AIH
--  Initial Date     :  14/07/2026
--  History          :
--    *01     14/07/2026  AIH  Initial Release. ACTIVE patients (Active=1 AND last appt <=730d) with no
--                             relevant future appointment, by retention route: Recall - Dentist /
--                             Recall - Hygiene (due <=4wk, no future exam / scale&polish), Cancelled Not
--                             Rebooked (cancelled <=90d, no future appt -- cancellation reason is empty
--                             on real Dentally data so no reason exclusion), Open Treatment No Appt (open
--                             course, no future appt). Generalises the earlier Fact_Recall_Gap. GOLD_AGG:
--                             reads Gold.Dim_Patients + Fact_Recalls + Fact_Treatment_Plans.
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Gold.usp_Load_Fact_Patient_At_Risk @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Patient_At_Risk]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Patient_At_Risk]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       smallint         = 1
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
        DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);

        DELETE FROM Gold.Fact_Patient_At_Risk;
        SET @My_Deletes = @@ROWCOUNT;

        -- Live (Unbooked/Booked) recall records per patient x discipline -> "a recall is chasing them".
        DROP TABLE IF EXISTS #live;
        SELECT r.fk_Patient, r.Tenant_ID,
            MAX(CASE WHEN r.Recall_Type LIKE '%Dentist%' THEN 1 ELSE 0 END) AS dent_live,
            MAX(CASE WHEN r.Recall_Type LIKE '%Hygien%'  THEN 1 ELSE 0 END) AS hyg_live
        INTO #live FROM Gold.Fact_Recalls r WHERE r.Status IN ('Unbooked','Booked')
        GROUP BY r.fk_Patient, r.Tenant_ID;

        -- ACTIVE base (Active flag AND seen within 730 days).
        DROP TABLE IF EXISTS #act;
        SELECT p.Tenant_ID, p.pk_Patient, ISNULL(s.pk_Practice_Site,-1) AS fk_Practice_Site,
            TRY_CAST(p.Dentist_Practitioner_ID AS INT)   AS dent_prac,
            TRY_CAST(p.Hygienist_Practitioner_ID AS INT) AS hyg_prac,
            p.Dentist_Recall_Date, p.Hygienist_Recall_Date, p.Next_Exam_Date, p.Next_Scale_Polish_Date,
            p.Next_Appointment_Date, p.Last_Cancelled_Appointment_Date
        INTO #act
        FROM Gold.Dim_Patients p
        LEFT JOIN Gold.Dim_Practice_Sites s ON s.Tenant_ID = p.Tenant_ID AND s.Site_ID = p.Site_ID
        WHERE ISNULL(p.Active,0) = 1 AND p.Last_Appointment_Date >= DATEADD(day,-730,@Today);

        -- Assemble the four routes.
        DROP TABLE IF EXISTS #ar;
        -- 1) Recall - Dentist: due <=4wk, no future exam booked
        SELECT a.Tenant_ID, a.pk_Patient AS fk_Patient, a.fk_Practice_Site, a.dent_prac AS prac_id,
            CAST('Recall - Dentist' AS VARCHAR(40)) AS Risk_Route,
            CAST(CASE WHEN ISNULL(lv.dent_live,0)=1 THEN 'Recall Active' ELSE 'No Recall' END AS VARCHAR(40)) AS Risk_Detail,
            a.Dentist_Recall_Date AS Reference_Date, ISNULL(lv.dent_live,0) AS Has_Live_Recall
        INTO #ar
        FROM #act a LEFT JOIN #live lv ON lv.fk_Patient = a.pk_Patient AND lv.Tenant_ID = a.Tenant_ID
        WHERE a.Dentist_Recall_Date BETWEEN @Today AND DATEADD(day,28,@Today)
          AND (a.Next_Exam_Date IS NULL OR a.Next_Exam_Date <= @Today)
        UNION ALL
        -- 2) Recall - Hygiene: due <=4wk, no future scale&polish booked
        SELECT a.Tenant_ID, a.pk_Patient, a.fk_Practice_Site, a.hyg_prac,
            'Recall - Hygiene',
            CASE WHEN ISNULL(lv.hyg_live,0)=1 THEN 'Recall Active' ELSE 'No Recall' END,
            a.Hygienist_Recall_Date, ISNULL(lv.hyg_live,0)
        FROM #act a LEFT JOIN #live lv ON lv.fk_Patient = a.pk_Patient AND lv.Tenant_ID = a.Tenant_ID
        WHERE a.Hygienist_Recall_Date BETWEEN @Today AND DATEADD(day,28,@Today)
          AND (a.Next_Scale_Polish_Date IS NULL OR a.Next_Scale_Polish_Date <= @Today)
        UNION ALL
        -- 3) Cancelled Not Rebooked: cancelled <=90d, no future appointment
        SELECT a.Tenant_ID, a.pk_Patient, a.fk_Practice_Site, a.dent_prac,
            'Cancelled Not Rebooked', NULL, a.Last_Cancelled_Appointment_Date, CAST(0 AS INT)
        FROM #act a
        WHERE a.Last_Cancelled_Appointment_Date >= DATEADD(day,-90,@Today)
          AND (a.Next_Appointment_Date IS NULL OR a.Next_Appointment_Date <= @Today)
        UNION ALL
        -- 4) Open Treatment No Appt: open course, no future appointment (one row per patient)
        SELECT a.Tenant_ID, a.pk_Patient, a.fk_Practice_Site, MAX(tp.fk_Practitioner),
            'Open Treatment No Appt', NULL, MIN(tp.Start_Date), CAST(0 AS INT)
        FROM #act a
        JOIN Gold.Fact_Treatment_Plans tp ON tp.fk_Patient = a.pk_Patient AND tp.Tenant_ID = a.Tenant_ID
        WHERE tp.Completed = 0 AND tp.Start_Date IS NOT NULL
          AND (a.Next_Appointment_Date IS NULL OR a.Next_Appointment_Date <= @Today)
        GROUP BY a.Tenant_ID, a.pk_Patient, a.fk_Practice_Site;

        INSERT INTO Gold.Fact_Patient_At_Risk (
            pk_At_Risk, Tenant_ID, fk_Patient, fk_Practice_Site, fk_Practitioner,
            Risk_Route, Risk_Detail, Reference_Date, Has_Live_Recall, DW_Created_At, DW_Updated_At)
        SELECT
            ROW_NUMBER() OVER (ORDER BY r.Tenant_ID, r.Risk_Route, r.fk_Patient),
            r.Tenant_ID, r.fk_Patient, r.fk_Practice_Site, ISNULL(pr.pk_Practitioner,-1),
            r.Risk_Route, r.Risk_Detail, r.Reference_Date, CAST(r.Has_Live_Recall AS BIT),
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #ar r
        LEFT JOIN Gold.Dim_Practitioners pr ON pr.Tenant_ID = r.Tenant_ID AND pr.Practitioner_ID = r.prac_id;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE IF EXISTS #live;
        DROP TABLE IF EXISTS #act;
        DROP TABLE IF EXISTS #ar;
        --*********************************
        --**** Procedure logic ends    ****
        --*********************************
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
