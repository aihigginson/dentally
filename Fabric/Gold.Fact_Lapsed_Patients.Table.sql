/****** Object:  Table [Gold].[Fact_Lapsed_Patients]    Script Date: 24/10/2026 ******/
-- One row per patient who is lapsed OR at risk, dated by the event, so a patient-level report
-- slices natively by Period / Site / Practitioner -- the star-schema fix for date-slicing a
-- dimension event (a Dim behaving like a fact, root-caused once before by Fact_Treatment_Plans,
-- V019). Aggregate lapsed counts live in Fact_Metric_Actuals; THIS fact exists for the patient
-- LIST, the reason breakdown, and the lapsing flow diagram on the Patient page.
--
-- ==> Lapsed_Type NOW CARRIES 'At Risk', WHICH HAS NOT LAPSED. <== Count lapsed patients over
-- this fact with SUM(Is_Lapsed), NEVER COUNT(*). The customer-facing lapsed figures and
-- [Net Patient Growth] read Fact_Metric_Actuals, not this table, so they cannot be moved by
-- the wider population -- but anything new that counts here can get it wrong by omission, and
-- Is_Lapsed is there so it cannot.
--
-- An at-risk row is dated last-reminded + 60 days, which is the ladder rung's own test in
-- Gold.usp_Load_Dim_Patients. Dentist_Recall_Date is the NEXT recall and is not that date.
--
-- The three flow columns: Last_Appointment_Reason (what they last came in for, rolled up to a
-- category), Last_Activity (what happened next -- DNA, a cancellation, or how far the recall
-- got), Lapsed_Type (where they are now).
--
-- Built full-rebuild (DROP/CREATE) by Gold.usp_Load_Fact_Lapsed_Patients. GOLD_AGG.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Lapsed_Patients]
GO
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
)
GO
