-- DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Patient_Lapse_Flow] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
----------------------------------------------------------------------------------------------------
--   Stored Procedure : Gold.usp_Load_Fact_Patient_Lapse_Flow
--   Author           : AIH
--   Intitial Date    : 24/10/2026
--   History          :
--       *01          24/10/2026  AIH  Initial Release
--
--   Purpose          : One row per lapsed OR at-risk patient, carrying the three stages of the
--                      lapsing flow for the alluvial: what they last came in for, what happened
--                      next, and where they are now. Patient grain so any node of the diagram can
--                      drill to the people it counts. Full rebuild (DROP/CREATE). GOLD_AGG.
--
--   Dependencies     : Gold Dim_Patients / Dim_Patient_Status / Fact_Appointments /
--                      Dim_Cancellation_Reasons / Fact_Recalls / Dim_Date.
--
--   To Run           : DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT;
--                      EXEC Gold.usp_Load_Fact_Patient_Lapse_Flow
--                           @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT;
----------------------------------------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Patient_Lapse_Flow]    Script Date: 24/10/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Patient_Lapse_Flow]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Patient_Lapse_Flow]
(
        @Mode           VARCHAR(100)     = 'TEST'
    ,   @Logging        SMALLINT         = 1
    ,   @Run_UUID       UNIQUEIDENTIFIER = NULL
    ,   @Run_Inserts    BIGINT OUT
    ,   @Run_Updates    BIGINT OUT
    ,   @Run_Deletes    BIGINT OUT
)
AS
BEGIN
        DECLARE @My_Inserts BIGINT = 0;
        DECLARE @My_Updates BIGINT = 0;
        DECLARE @My_Deletes BIGINT = 0;
        SET NOCOUNT ON;
        BEGIN TRY
                --*********************************
                --****  Procedure logic starts ****
                --*********************************

                -- ---- the population --------------------------------------------------------
                -- Lapsed (either kind) or at risk, and reportable. The archive rung is excluded
                -- the same way Fact_Lapsed_Patients excludes it: a patient who was never had
                -- cannot be lost, and at the live tenant that is 19,471 pre-migration records.
                DROP TABLE IF EXISTS #pop;
                SELECT  p.Tenant_ID,
                        p.pk_Patient                            AS fk_Patient,
                        p.Patient_ID                            AS bk_Patient_ID,
                        ISNULL(p.fk_Current_Dentist, -1)        AS fk_Practitioner,
                        p.fk_Patient_Status,
                        CASE s.Status_Code
                             WHEN 'LAPSED_SET_INACTIVE'        THEN 'Set Inactive'
                             WHEN 'LAPSED_NO_VISIT_24M'        THEN 'Calculated Inactive'
                             WHEN 'RECALL_SENT_NO_REPLY_GT2M'  THEN 'At Risk'
                        END                                     AS Current_Status,
                        -- ==> PLAN MEMBERSHIP IS A CAPITATION RATE, NOT A NAME. <== Standard
                        -- Payment Plan holds 12 values at the live tenant, mostly plan names
                        -- (seven Denplan variants) rather than categories -- too many for a
                        -- slicer and not a taxonomy. A plan patient is one whose plan carries a
                        -- rate in Input.Plan_Capitation_Rate, which is the rule already settled
                        -- for who counts as a plan patient. Every Denplan variant has one and
                        -- nothing else does.
                        CASE WHEN p.Standard_Payment_Plan = 'NHS'     THEN 'NHS'
                             WHEN cr.Payment_Plan_ID IS NOT NULL      THEN 'Plan'
                             WHEN p.Standard_Payment_Plan = 'Private' THEN 'Private'
                             ELSE 'Other' END                        AS Patient_Category
                INTO    #pop
                FROM    Gold.Dim_Patients p
                JOIN    Gold.Dim_Patient_Status s ON s.pk_Patient_Status = p.fk_Patient_Status
                LEFT JOIN (SELECT DISTINCT Tenant_ID, Payment_Plan_ID FROM Input.Plan_Capitation_Rate) cr
                       ON cr.Tenant_ID = p.Tenant_ID AND cr.Payment_Plan_ID = p.Payment_Plan_ID
                WHERE   p.pk_Patient > 0
                  AND   s.Is_Reportable = 1
                  AND   s.Status_Code IN ('LAPSED_SET_INACTIVE', 'LAPSED_NO_VISIT_24M',
                                          'RECALL_SENT_NO_REPLY_GT2M');

                -- ---- stage 1: the last COMPLETED appointment -------------------------------
                -- ---- the categories the map actually defines ------------------------------
                -- Fact_Appointments.Appointment_Reason holds the mapped Category where the map
                -- matched and the RAW reason text where it did not, so membership of this set
                -- is exactly the test of "was this reason ever categorised".
                DROP TABLE IF EXISTS #reason_cat;
                SELECT  DISTINCT Category
                INTO    #reason_cat
                FROM    Silver.Appointment_Reason_Map
                WHERE   NULLIF(TRIM(Category), '') IS NOT NULL;

                -- Completed only. A cancelled or missed appointment is stage 2, not stage 1 --
                -- "what they last came in for" means they came in.
                DROP TABLE IF EXISTS #last_appt;
                SELECT  a.Tenant_ID, a.fk_Patient,
                        a.fk_Date_Start, a.fk_Practice_Site, a.Appointment_Reason,
                        ROW_NUMBER() OVER (PARTITION BY a.Tenant_ID, a.fk_Patient
                                           ORDER BY a.fk_Date_Start DESC, a.pk_Appointment DESC) AS rn
                INTO    #last_appt
                FROM    Gold.Fact_Appointments a
                JOIN    #pop q ON q.Tenant_ID = a.Tenant_ID AND q.fk_Patient = a.fk_Patient
                WHERE   a.State = 'Completed'
                  AND   a.fk_Date_Start <> -1;

                -- ---- stage 2a: the last DNA or cancellation --------------------------------
                -- Mapped through Dim_Cancellation_Reasons, which only tells practice from
                -- patient because V238 finally filled Input.Cancellation_Reason_Map.
                DROP TABLE IF EXISTS #last_event;
                SELECT  a.Tenant_ID, a.fk_Patient, a.fk_Date_Start,
                        CASE WHEN ISNULL(a.Is_DNA, 0) = 1 THEN 'DNA'
                             WHEN d.Standard_Cancellation_Reason LIKE 'Practice%' THEN 'Cancellation Practice'
                             WHEN d.Standard_Cancellation_Reason LIKE 'Patient%'  THEN 'Cancellation Patient'
                             ELSE 'Cancellation Other' END   AS Last_Activity,
                        ROW_NUMBER() OVER (PARTITION BY a.Tenant_ID, a.fk_Patient
                                           ORDER BY a.fk_Date_Start DESC, a.pk_Appointment DESC) AS rn
                INTO    #last_event
                FROM    Gold.Fact_Appointments a
                JOIN    #pop q ON q.Tenant_ID = a.Tenant_ID AND q.fk_Patient = a.fk_Patient
                LEFT JOIN Gold.Dim_Cancellation_Reasons d
                       ON d.pk_Cancellation_Reason = a.fk_Cancellation_Reason
                WHERE   a.fk_Date_Start <> -1
                  AND   (ISNULL(a.Is_DNA, 0) = 1 OR ISNULL(a.Is_Cancelled, 0) = 1);

                -- ---- stage 2b: how far the recall got --------------------------------------
                -- ==> COUNT THE CONTACTS; THE SECOND-REMINDER FIELDS ARE DEAD. <== Dentally
                -- populates NEITHER Second_Reminder_Sent_At NOR Second_Reminder_ID -- both are
                -- empty on all 9,307 of Maple's recalls, right back in Bronze. Reading them made
                -- "2nd Reminder" unreachable and the practice look as though it never chased
                -- twice. Times_Contacted says otherwise: 5,749 recalls have been chased more
                -- than once, up to six times.
                DROP TABLE IF EXISTS #recall;
                SELECT  r.Tenant_ID, r.fk_Patient,
                        MAX(ISNULL(TRY_CAST(r.Times_Contacted AS INT), 0)) AS contacts,
                        MAX(CASE WHEN ISNULL(r.Is_Reminder_Sent, 0) = 1 THEN 1 ELSE 0 END) AS sent
                INTO    #recall
                FROM    Gold.Fact_Recalls r
                JOIN    #pop q ON q.Tenant_ID = r.Tenant_ID AND q.fk_Patient = r.fk_Patient
                GROUP BY r.Tenant_ID, r.fk_Patient;

                -- ---- build ------------------------------------------------------------------
                DROP TABLE IF EXISTS [Gold].[Fact_Patient_Lapse_Flow];

                CREATE TABLE [Gold].[Fact_Patient_Lapse_Flow] (
                        [pk_Patient_Lapse_Flow]       BIGINT IDENTITY NOT NULL,
                        [Tenant_ID]                   INT             NOT NULL,
                        [bk_Patient_ID]               INT             NULL,
                        [fk_Patient]                  BIGINT          NOT NULL,
                        [fk_Practitioner]             BIGINT          NOT NULL,
                        [fk_Practice_Site]            BIGINT          NOT NULL,
                        [fk_Patient_Status]           INT             NOT NULL,
                        [fk_Date_Last_Appointment]    INT             NULL,
                        [Last_Appointment_Reason]     VARCHAR(100)    NULL,
                        [Last_Activity]               VARCHAR(50)     NULL,
                        [Current_Status]              VARCHAR(50)     NULL,
                        [Patient_Category]            VARCHAR(50)     NULL,
                        [Patient_Lapse_Flow_Count]    INT             NOT NULL,
                        [DW_Created_At]               DATETIME2(3)    NOT NULL,
                        [DW_Updated_At]               DATETIME2(3)    NOT NULL
                );

                INSERT INTO [Gold].[Fact_Patient_Lapse_Flow]
                        (Tenant_ID, bk_Patient_ID, fk_Patient, fk_Practitioner, fk_Practice_Site,
                         fk_Patient_Status, fk_Date_Last_Appointment, Last_Appointment_Reason,
                         Last_Activity, Current_Status, Patient_Category, Patient_Lapse_Flow_Count,
                         DW_Created_At, DW_Updated_At)
                SELECT  q.Tenant_ID,
                        q.bk_Patient_ID,
                        q.fk_Patient,
                        q.fk_Practitioner,
                        -- ==> THE SITE COMES FROM THE LAST APPOINTMENT. <== A patient has no site
                        -- of their own; the place they last attended is the honest answer, and it
                        -- is what makes the row slice by Area and Region now those hang off site.
                        ISNULL(la.fk_Practice_Site, -1)                 AS fk_Practice_Site,
                        q.fk_Patient_Status,
                        la.fk_Date_Start                                AS fk_Date_Last_Appointment,
                        -- No appointment at all is a STATE, not an uncategorised reason, so it
                        -- keeps its own node. Anything the map never categorised rolls into
                        -- 'Other' -- the behaviour the map's own header documents.
                        CASE WHEN la.fk_Patient IS NULL     THEN 'No Appointment'
                             WHEN rcat.Category IS NOT NULL THEN la.Appointment_Reason
                             ELSE 'Other' END                       AS Last_Appointment_Reason,
                        -- ==> AN APPOINTMENT EVENT BEATS A RECALL STATE. <== A DNA or a
                        -- cancellation is something that HAPPENED; a recall state is a thing that
                        -- did not. Where both exist the event wins, and only patients with no
                        -- such event fall through to how far their recall got. Change this CASE
                        -- if "last" should mean strictly most recent in time instead.
                        -- '2nd Reminder' means two OR MORE contacts: the counter runs to six
                        -- and the diagram has one band for "chased again", not five.
                        CASE WHEN le.Last_Activity IS NOT NULL THEN le.Last_Activity
                             WHEN rc.fk_Patient IS NULL        THEN 'Recall Not Set'
                             WHEN rc.contacts >= 2             THEN '2nd Reminder'
                             WHEN rc.contacts = 1              THEN '1st Reminder'
                             WHEN rc.sent     = 1              THEN '1st Reminder'
                             ELSE 'Recall Not Sent' END        AS Last_Activity,
                        q.Current_Status,
                        q.Patient_Category,
                        1,
                        SYSUTCDATETIME(), SYSUTCDATETIME()
                FROM    #pop q
                LEFT JOIN #last_appt  la ON la.Tenant_ID = q.Tenant_ID AND la.fk_Patient = q.fk_Patient AND la.rn = 1
                LEFT JOIN #last_event le ON le.Tenant_ID = q.Tenant_ID AND le.fk_Patient = q.fk_Patient AND le.rn = 1
                LEFT JOIN #recall     rc ON rc.Tenant_ID = q.Tenant_ID AND rc.fk_Patient = q.fk_Patient
                LEFT JOIN #reason_cat rcat ON rcat.Category = la.Appointment_Reason;

                SET @My_Inserts = @@ROWCOUNT;

                DROP TABLE IF EXISTS #pop;
                DROP TABLE IF EXISTS #last_appt;
                DROP TABLE IF EXISTS #last_event;
                DROP TABLE IF EXISTS #recall;
                DROP TABLE IF EXISTS #reason_cat;

                --*********************************
                --****  Procedure logic ends   ****
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
