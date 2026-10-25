-- DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Lapsed_Patients] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
----------------------------------------------------------------------------------------------------
--   Stored Procedure : Gold.usp_Load_Fact_Lapsed_Patients
--   Author           : AIH
--   Intitial Date    : 01/08/2026
--   History          :
--       *01          01/08/2026  AIH  Initial Release
--
--   Purpose          : Materialises one row per lapsed patient (Dim_Patients.Lapsed_Type IS NOT NULL),
--                      dated by the lapse date, so a patient-level lapsed report slices natively by
--                      Period / Site / Practitioner (and Payment Plan) -- the star-schema alternative
--                      to date-relating the patient dimension. Carries Lapsed_Type / Lapsed_Reason /
--                      Lapsed_Date for the deactivated-vs-long-silent breakdown. Full rebuild
--                      (DROP/CREATE). GOLD_AGG -- reads Gold.Dim_Patients (+ dims for surrogate keys).
--
--   Dependencies     : Gold Dim_Patients / Dim_Practitioners / Dim_Practice_Sites / Dim_Payment_Plans.
--
--   To Run           : DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT;
--                      EXEC Gold.usp_Load_Fact_Lapsed_Patients
--                           @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
----------------------------------------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Lapsed_Patients]    Script Date: 08/01/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Lapsed_Patients]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Lapsed_Patients]
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
                -- The lifecycle ladder is the single place the judgement lives (V229), so the
                -- rungs are named rather than inferred from Lapsed_Type being populated: that
                -- is the only way to reach the at-risk rung, which has no Lapsed_Type at all.
                -- ==> THE ARCHIVE IS NOT LAPSED. <== A patient with no completed appointment,
                -- no invoice and no payment anywhere was never had, so they cannot have been
                -- lost. They are overwhelmingly pre-migration records -- 19,471 of the 21,761
                -- rows this fact once carried at the live tenant, which made every lapsed count
                -- in the product ten times too big. Is_Reportable carries that exclusion.
                DROP TABLE IF EXISTS #pop;
                SELECT  p.Tenant_ID,
                        p.pk_Patient                            AS fk_Patient,
                        p.Patient_ID                            AS bk_Patient_ID,
                        p.fk_Patient_Status,
                        p.Dentist_Practitioner_ID,
                        p.Site_ID,
                        p.Payment_Plan_ID,
                        p.fk_Date_Lapsed,
                        p.Lapsed_Date,
                        s.Status_Code,
                        COALESCE(p.Lapsed_Type, 'At Risk')      AS Lapsed_Type,
                        COALESCE(p.Lapsed_Reason,
                                 'No response 2 months after being reminded') AS Lapsed_Reason,
                        CASE WHEN p.Lapsed_Type IS NOT NULL THEN 1 ELSE 0 END AS Is_Lapsed,
                        -- ==> PLAN MEMBERSHIP IS A CAPITATION RATE, NOT A NAME. <== Standard
                        -- Payment Plan holds 12 values at the live tenant, mostly plan names
                        -- (seven Denplan variants) rather than categories -- too many for a
                        -- slicer and not a taxonomy. A plan patient is one whose plan carries a
                        -- rate in Input.Plan_Capitation_Rate, the rule already settled for who
                        -- counts as a plan patient. Every Denplan variant has one; nothing else
                        -- does.
                        CASE WHEN p.Standard_Payment_Plan = 'NHS'     THEN 'NHS'
                             WHEN cr.Payment_Plan_ID IS NOT NULL      THEN 'Plan'
                             WHEN p.Standard_Payment_Plan = 'Private' THEN 'Private'
                             ELSE 'Other' END                   AS Patient_Category
                INTO    #pop
                FROM    [Gold].[Dim_Patients] p
                JOIN    [Gold].[Dim_Patient_Status] s ON s.pk_Patient_Status = p.fk_Patient_Status
                LEFT JOIN (SELECT DISTINCT Tenant_ID, Payment_Plan_ID FROM [Input].[Plan_Capitation_Rate]) cr
                       ON cr.Tenant_ID = p.Tenant_ID AND cr.Payment_Plan_ID = p.Payment_Plan_ID
                WHERE   p.pk_Patient > 0
                  AND   s.Is_Reportable = 1
                  AND   s.Status_Code IN ('LAPSED_SET_INACTIVE', 'LAPSED_NO_VISIT_24M',
                                          'RECALL_SENT_NO_REPLY_GT2M');

                -- ---- the date an at-risk patient became at risk ----------------------------
                -- Last reminded + 60 days, because that is literally the ladder's own test.
                -- Date keys are days since the epoch, so + 60 is the key arithmetic and
                -- Dim_Date turns it back into a date for Lapsed_Date.
                -- ==> THE SAME RECALL THE LADDER JUDGED, NOT THE LATEST REMINDER. <==
                -- Gold.usp_Load_Dim_Patients picks ONE recall per patient, the latest by
                -- Due_Date then Id, and tests THAT recall's last-reminded date against 60
                -- days. Taking MAX across all of a patient's recalls instead put 46 of 1,167
                -- at-risk rows in the FUTURE: a patient with an older-DUE recall chased more
                -- recently gives a later maximum than the rung was judged on. An event dated
                -- after today belongs to no past period at all.
                DROP TABLE IF EXISTS #at_risk_date;
                SELECT  x.Tenant_ID, x.fk_Patient, x.fk_Date_Reminded + 60 AS fk_Date_At_Risk
                INTO    #at_risk_date
                FROM  ( SELECT  r.Tenant_ID, r.fk_Patient,
                                COALESCE(NULLIF(r.fk_Date_Last_Reminded, -1),
                                         NULLIF(r.fk_Date_First_Reminder, -1)) AS fk_Date_Reminded,
                                ROW_NUMBER() OVER (PARTITION BY r.Tenant_ID, r.fk_Patient
                                                   ORDER BY r.fk_Date_Due DESC, r.bk_Recall_ID DESC) AS rn
                        FROM    [Gold].[Fact_Recalls] r
                        JOIN    #pop q ON q.Tenant_ID = r.Tenant_ID AND q.fk_Patient = r.fk_Patient
                        WHERE   q.Status_Code = 'RECALL_SENT_NO_REPLY_GT2M' ) x
                WHERE   x.rn = 1
                  AND   x.fk_Date_Reminded IS NOT NULL;

                -- ---- the categories the reason map actually defines ------------------------
                -- Fact_Appointments.Appointment_Reason holds the mapped Category where the map
                -- matched and the RAW reason text where it did not, so membership of this set
                -- is exactly the test of "was this reason ever categorised". Without the
                -- roll-up the first column of the flow is 40 nodes, 35 of them under ten
                -- patients. Silver.Appointment_Reason_Map's own header documents 'Other' as the
                -- intended default; Gold.usp_Load_Fact_Appointments does not honour it, and is
                -- deliberately not changed here -- far too many measures read that column.
                DROP TABLE IF EXISTS #reason_cat;
                SELECT  DISTINCT Category
                INTO    #reason_cat
                FROM    [Silver].[Appointment_Reason_Map]
                WHERE   NULLIF(TRIM(Category), '') IS NOT NULL;

                -- ---- stage 1: the last COMPLETED appointment -------------------------------
                -- Completed only: "what they last came in for" means they came in. A cancelled
                -- or missed appointment is stage 2.
                DROP TABLE IF EXISTS #last_appt;
                SELECT  a.Tenant_ID, a.fk_Patient, a.fk_Date_Start, a.Appointment_Reason,
                        ROW_NUMBER() OVER (PARTITION BY a.Tenant_ID, a.fk_Patient
                                           ORDER BY a.fk_Date_Start DESC, a.pk_Appointment DESC) AS rn
                INTO    #last_appt
                FROM    [Gold].[Fact_Appointments] a
                JOIN    #pop q ON q.Tenant_ID = a.Tenant_ID AND q.fk_Patient = a.fk_Patient
                WHERE   a.State = 'Completed'
                  AND   a.fk_Date_Start <> -1;

                -- ---- stage 2a: the last DNA or cancellation --------------------------------
                -- Mapped through Dim_Cancellation_Reasons, which only tells practice from
                -- patient because V238 finally filled Input.Cancellation_Reason_Map.
                DROP TABLE IF EXISTS #last_event;
                SELECT  a.Tenant_ID, a.fk_Patient,
                        CASE WHEN ISNULL(a.Is_DNA, 0) = 1 THEN 'DNA'
                             WHEN d.Standard_Cancellation_Reason LIKE 'Practice%' THEN 'Cancellation Practice'
                             WHEN d.Standard_Cancellation_Reason LIKE 'Patient%'  THEN 'Cancellation Patient'
                             ELSE 'Cancellation Other' END   AS Last_Activity,
                        ROW_NUMBER() OVER (PARTITION BY a.Tenant_ID, a.fk_Patient
                                           ORDER BY a.fk_Date_Start DESC, a.pk_Appointment DESC) AS rn
                INTO    #last_event
                FROM    [Gold].[Fact_Appointments] a
                JOIN    #pop q ON q.Tenant_ID = a.Tenant_ID AND q.fk_Patient = a.fk_Patient
                LEFT JOIN [Gold].[Dim_Cancellation_Reasons] d
                       ON d.pk_Cancellation_Reason = a.fk_Cancellation_Reason
                WHERE   a.fk_Date_Start <> -1
                  AND   (ISNULL(a.Is_DNA, 0) = 1 OR ISNULL(a.Is_Cancelled, 0) = 1);

                -- ---- stage 2b: how far the recall got --------------------------------------
                -- ==> COUNT THE CONTACTS; THE SECOND-REMINDER FIELDS ARE DEAD. <== Dentally
                -- populates NEITHER Second_Reminder_Sent_At NOR Second_Reminder_ID -- both are
                -- empty on all 9,307 of Maple's recalls, right back in Bronze. Reading them
                -- made "2nd Reminder" unreachable and the practice look as though it never
                -- chased twice. Times_Contacted says otherwise: 5,749 recalls have been chased
                -- more than once, up to six times.
                DROP TABLE IF EXISTS #recall;
                SELECT  r.Tenant_ID, r.fk_Patient,
                        MAX(ISNULL(TRY_CAST(r.Times_Contacted AS INT), 0)) AS contacts,
                        MAX(CASE WHEN ISNULL(r.Is_Reminder_Sent, 0) = 1 THEN 1 ELSE 0 END) AS sent
                INTO    #recall
                FROM    [Gold].[Fact_Recalls] r
                JOIN    #pop q ON q.Tenant_ID = r.Tenant_ID AND q.fk_Patient = r.fk_Patient
                GROUP BY r.Tenant_ID, r.fk_Patient;

                DROP TABLE IF EXISTS [Gold].[Fact_Lapsed_Patients];

                CREATE TABLE [Gold].[Fact_Lapsed_Patients] (
                        [pk_Lapsed_Patient]       BIGINT IDENTITY NOT NULL,
                        [Tenant_ID]               INT             NOT NULL,
                        [bk_Patient_ID]           INT             NOT NULL,
                        [fk_Patient]              BIGINT          NOT NULL,
                        [fk_Practitioner]         BIGINT          NOT NULL,
                        [fk_Practice_Site]        BIGINT          NOT NULL,
                        [fk_Payment_Plan]         BIGINT          NOT NULL,
                        [fk_Date_Lapsed]          BIGINT          NOT NULL,
                        [fk_Patient_Status]       INT             NOT NULL,
                        -- 'Set as inactive' | 'Calculated as inactive' | 'At Risk'.
                        [Lapsed_Type]             VARCHAR(30)     NULL,
                        [Lapsed_Reason]           VARCHAR(255)    NULL,
                        [Lapsed_Date]             DATE            NULL,
                        -- ==> 1 = ACTUALLY LAPSED, 0 = AT RISK. <== Anything counting lapsed
                        -- patients over this fact must SUM(Is_Lapsed), never COUNT(*).
                        [Is_Lapsed]               INT             NOT NULL,
                        -- The three stages of the lapsing flow, for the alluvial on the
                        -- Patient page and the patient list it drills to.
                        [fk_Date_Last_Appointment] INT            NULL,
                        [Last_Appointment_Reason] VARCHAR(100)    NULL,
                        -- What Dentally actually recorded, before the roll-up. The category
                        -- above drives the diagram; this drives the list, where "Broken Tooth"
                        -- says something "Other" does not.
                        [Last_Appointment_Reason_Detail] VARCHAR(200) NULL,
                        [Last_Activity]           VARCHAR(50)     NULL,
                        -- Private / NHS / Plan / Other. Plan membership is a capitation rate,
                        -- not a name -- fk_Payment_Plan names the plan, this categorises it.
                        [Patient_Category]        VARCHAR(50)     NULL,
                        [Lapsed_Patient_Count]    INT             NOT NULL,
                        [DW_Created_At]           DATETIME2(3)    NOT NULL
                );

                INSERT INTO [Gold].[Fact_Lapsed_Patients]
                        (Tenant_ID, bk_Patient_ID, fk_Patient, fk_Practitioner, fk_Practice_Site,
                         fk_Payment_Plan, fk_Date_Lapsed, fk_Patient_Status, Lapsed_Type,
                         Lapsed_Reason, Lapsed_Date, Is_Lapsed, fk_Date_Last_Appointment,
                         Last_Appointment_Reason, Last_Appointment_Reason_Detail, Last_Activity, Patient_Category,
                         Lapsed_Patient_Count, DW_Created_At)
                SELECT  q.Tenant_ID, q.bk_Patient_ID, q.fk_Patient,
                        ISNULL(dpr.pk_Practitioner, -1),
                        ISNULL(dps.pk_Practice_Site, -1),
                        ISNULL(dpp.pk_Payment_Plan, -1),
                        -- A lapsed patient is dated by their lapse; an at-risk patient by the
                        -- day they fell silent too long. Never -1: a row that cannot be dated
                        -- cannot appear in a period and the guards reject it.
                        COALESCE(NULLIF(q.fk_Date_Lapsed, -1), ar.fk_Date_At_Risk, -1),
                        q.fk_Patient_Status,
                        q.Lapsed_Type, q.Lapsed_Reason,
                        COALESCE(q.Lapsed_Date, dt.Full_Date),
                        q.Is_Lapsed,
                        la.fk_Date_Start,
                        -- No appointment at all is a STATE, not an uncategorised reason, so it
                        -- keeps its own node in the flow.
                        CASE WHEN la.fk_Patient IS NULL     THEN 'No Appointment'
                             WHEN rcat.Category IS NOT NULL THEN la.Appointment_Reason
                             ELSE 'Other' END,
                        -- The same row, un-rolled-up. 'No Appointment' is repeated rather than
                        -- left NULL so a list never shows a blank cell for a real state.
                        CASE WHEN la.fk_Patient IS NULL THEN 'No Appointment'
                             ELSE NULLIF(TRIM(la.Appointment_Reason), '') END,
                        -- ==> AN APPOINTMENT EVENT BEATS A RECALL STATE. <== A DNA or a
                        -- cancellation is something that HAPPENED; a recall state is a thing
                        -- that did not. Where both exist the event wins, and only patients with
                        -- no such event fall through to how far their recall got.
                        CASE WHEN le.Last_Activity IS NOT NULL THEN le.Last_Activity
                             WHEN rc.fk_Patient IS NULL        THEN 'Recall Not Set'
                             WHEN rc.contacts >= 2             THEN '2nd Reminder'
                             WHEN rc.contacts = 1              THEN '1st Reminder'
                             WHEN rc.sent     = 1              THEN '1st Reminder'
                             ELSE 'Recall Not Sent' END,
                        q.Patient_Category,
                        1, SYSUTCDATETIME()
                FROM    #pop q
                LEFT JOIN [Gold].[Dim_Practitioners]  dpr ON dpr.Tenant_ID = q.Tenant_ID AND dpr.Practitioner_ID = q.Dentist_Practitioner_ID
                LEFT JOIN [Gold].[Dim_Practice_Sites] dps ON dps.Tenant_ID = q.Tenant_ID AND dps.Site_ID         = q.Site_ID
                LEFT JOIN [Gold].[Dim_Payment_Plans]  dpp ON dpp.Tenant_ID = q.Tenant_ID AND dpp.Payment_Plan_ID = q.Payment_Plan_ID
                LEFT JOIN #at_risk_date ar   ON ar.Tenant_ID = q.Tenant_ID AND ar.fk_Patient = q.fk_Patient
                LEFT JOIN [Gold].[Dim_Date] dt ON dt.pk_Date = ar.fk_Date_At_Risk
                LEFT JOIN #last_appt    la   ON la.Tenant_ID = q.Tenant_ID AND la.fk_Patient = q.fk_Patient AND la.rn = 1
                LEFT JOIN #last_event   le   ON le.Tenant_ID = q.Tenant_ID AND le.fk_Patient = q.fk_Patient AND le.rn = 1
                LEFT JOIN #recall       rc   ON rc.Tenant_ID = q.Tenant_ID AND rc.fk_Patient = q.fk_Patient
                LEFT JOIN #reason_cat   rcat ON rcat.Category = la.Appointment_Reason;

                SET @My_Inserts = @@ROWCOUNT;

                DROP TABLE IF EXISTS #pop;
                DROP TABLE IF EXISTS #at_risk_date;
                DROP TABLE IF EXISTS #reason_cat;
                DROP TABLE IF EXISTS #last_appt;
                DROP TABLE IF EXISTS #last_event;
                DROP TABLE IF EXISTS #recall;

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
