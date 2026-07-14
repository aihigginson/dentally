--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Recall_Gap] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Recall_Gap
--  Author           :  AIH
--  Initial Date     :  14/07/2026
--  History          :
--    *01     14/07/2026  AIH  Initial Release. One row per (active patient x discipline) whose PATIENT
--                             recall date (Dim_Patients.Dentist_Recall_Date / Hygienist_Recall_Date) is
--                             within the next 4 weeks -- the Retention Outlook worklist. Cohort:
--                             Booked / Gap - Recall Active (has a live Unbooked recall record) /
--                             Gap - No Recall (nothing chasing them). GOLD_AGG: reads Gold.Dim_Patients
--                             + Gold.Fact_Recalls, so the Gold->Agg rule orders it after those.
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Gold.usp_Load_Fact_Recall_Gap @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Recall_Gap]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Recall_Gap]
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

        DELETE FROM Gold.Fact_Recall_Gap;
        SET @My_Deletes = @@ROWCOUNT;

        -- Live (Unbooked) recall records per patient x discipline: "a recall is actively chasing them".
        DROP TABLE IF EXISTS #live;
        SELECT r.fk_Patient, r.Tenant_ID,
            MAX(CASE WHEN r.Recall_Type LIKE '%Dentist%' THEN 1 ELSE 0 END) AS dent_live,
            MAX(CASE WHEN r.Recall_Type LIKE '%Hygien%'  THEN 1 ELSE 0 END) AS hyg_live
        INTO #live FROM Gold.Fact_Recalls r WHERE r.Status IN ('Unbooked','Booked')
        GROUP BY r.fk_Patient, r.Tenant_ID;

        -- One row per (active patient x discipline) due in the next 4 weeks.
        DROP TABLE IF EXISTS #gap;
        SELECT b.Tenant_ID, b.pk_Patient AS fk_Patient, ISNULL(s.pk_Practice_Site,-1) AS fk_Practice_Site,
            CAST('Dentist' AS VARCHAR(20)) AS Discipline, b.Dentist_Recall_Date AS Recall_Date,
            DATEDIFF(day, @Today, b.Dentist_Recall_Date) AS Days_Until_Due,
            CASE WHEN b.Next_Exam_Date > @Today THEN 1 ELSE 0 END AS Has_Appointment,
            ISNULL(lv.dent_live,0) AS Has_Live_Recall, b.Next_Exam_Date AS Next_Relevant_Appt_Date,
            TRY_CAST(b.Dentist_Practitioner_ID AS INT) AS prac_id
        INTO #gap
        FROM Gold.Dim_Patients b
        LEFT JOIN #live lv                     ON lv.fk_Patient = b.pk_Patient AND lv.Tenant_ID = b.Tenant_ID
        LEFT JOIN Gold.Dim_Practice_Sites s    ON s.Tenant_ID   = b.Tenant_ID  AND s.Site_ID    = b.Site_ID
        WHERE ISNULL(b.Active,0) = 1 AND b.Last_Appointment_Date >= DATEADD(day,-730,@Today)
          AND b.Dentist_Recall_Date BETWEEN @Today AND DATEADD(day,28,@Today)
        UNION ALL
        SELECT b.Tenant_ID, b.pk_Patient, ISNULL(s.pk_Practice_Site,-1),
            'Hygiene', b.Hygienist_Recall_Date, DATEDIFF(day, @Today, b.Hygienist_Recall_Date),
            CASE WHEN b.Next_Scale_Polish_Date > @Today THEN 1 ELSE 0 END,
            ISNULL(lv.hyg_live,0), b.Next_Scale_Polish_Date,
            TRY_CAST(b.Hygienist_Practitioner_ID AS INT)
        FROM Gold.Dim_Patients b
        LEFT JOIN #live lv                     ON lv.fk_Patient = b.pk_Patient AND lv.Tenant_ID = b.Tenant_ID
        LEFT JOIN Gold.Dim_Practice_Sites s    ON s.Tenant_ID   = b.Tenant_ID  AND s.Site_ID    = b.Site_ID
        WHERE ISNULL(b.Active,0) = 1 AND b.Last_Appointment_Date >= DATEADD(day,-730,@Today)
          AND b.Hygienist_Recall_Date BETWEEN @Today AND DATEADD(day,28,@Today);

        INSERT INTO Gold.Fact_Recall_Gap (
            pk_Recall_Gap, Tenant_ID, fk_Patient, fk_Practice_Site, fk_Practitioner,
            Discipline, Recall_Date, Days_Until_Due, Cohort, Has_Appointment, Has_Live_Recall,
            Next_Relevant_Appt_Date, DW_Created_At, DW_Updated_At)
        SELECT
            ROW_NUMBER() OVER (ORDER BY g.Tenant_ID, g.Discipline, g.fk_Patient),
            g.Tenant_ID, g.fk_Patient, g.fk_Practice_Site, ISNULL(pr.pk_Practitioner,-1),
            g.Discipline, g.Recall_Date, g.Days_Until_Due,
            CASE WHEN g.Has_Appointment = 1 THEN 'Booked'
                 WHEN g.Has_Live_Recall  = 1 THEN 'Gap - Recall Active'
                 ELSE 'Gap - No Recall' END,
            CAST(g.Has_Appointment AS BIT), CAST(g.Has_Live_Recall AS BIT), g.Next_Relevant_Appt_Date,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #gap g
        LEFT JOIN Gold.Dim_Practitioners pr ON pr.Tenant_ID = g.Tenant_ID AND pr.Practitioner_ID = g.prac_id;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE IF EXISTS #live;
        DROP TABLE IF EXISTS #gap;
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
