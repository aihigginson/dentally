/****** Object:  Table [Gold].[Fact_Patient_Lapse_Flow]    Script Date: 24/10/2026 ******/
-- One row per patient who is lapsed or at risk, carrying the three stages of the lapsing
-- flow: what they last came in for, what happened next, and where they are now.
--
-- ==> NOT AN EXTENSION OF Fact_Lapsed_Patients. <== That table holds patients who have
-- ALREADY lapsed, and its counts are the lapsed figures V234 corrected. "At risk" patients
-- have not lapsed, so adding them there would move a customer-visible number for the second
-- time in a month. This is a separate fact with a wider population and a different purpose.
--
-- ==> BOTH fk_Practitioner AND fk_Practice_Site ARE ALWAYS REAL. <== Never a -1 sentinel.
-- The point of the table is that a clinician can see where they are losing patients, which
-- needs the two keys on the SAME row -- the thing Fact_Metric_Actuals never does.
--
-- Patient grain, so a report can drill from any node of the flow to the people it counts.
-- A drillthrough page binds COLUMNS, not measures, and these are columns.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Patient_Lapse_Flow]
GO
CREATE TABLE [Gold].[Fact_Patient_Lapse_Flow](
    [pk_Patient_Lapse_Flow]      [bigint]       NOT NULL,
    [Tenant_ID]                  [int]          NOT NULL,
    [bk_Patient_ID]              [int]          NULL,
    [fk_Patient]                 [bigint]       NOT NULL,
    -- The dentist who OWNED the patient when they drifted -- Dim_Patients.fk_Current_Dentist,
    -- derived from the exam-ownership spell rule, not whoever happened to see them last.
    [fk_Practitioner]            [bigint]       NOT NULL,
    [fk_Practice_Site]           [bigint]       NOT NULL,
    [fk_Patient_Status]          [int]          NOT NULL,
    [fk_Date_Last_Appointment]   [int]          NULL,
    [fk_Date_Last_Activity]      [int]          NULL,
    -- Stage 1: the mapped category of their last completed appointment.
    [Last_Appointment_Reason]    [varchar](100) NULL,
    -- Stage 2: DNA, Cancellation Practice / Patient / Other, Recall Not Set, Recall Not Sent,
    -- 1st Reminder, 2nd Reminder.
    [Last_Activity]              [varchar](50)  NULL,
    [Last_Activity_Date]         [date]         NULL,
    -- Stage 3: Set Inactive, Calculated Inactive, At Risk.
    [Current_Status]             [varchar](50)  NULL,
    -- Private / NHS / Plan / Other. Plan membership is a capitation rate, not a name.
    [Patient_Category]           [varchar](50)  NULL,
    [Days_Since_Last_Appointment] [int]         NULL,
    [Patient_Lapse_Flow_Count]   [int]          NOT NULL,
    [DW_Created_At]              [datetime2](3) NOT NULL,
    [DW_Updated_At]              [datetime2](3) NOT NULL
)
GO
