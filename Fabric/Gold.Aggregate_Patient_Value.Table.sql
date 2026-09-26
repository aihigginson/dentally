/****** Object:  Table [Gold].[Aggregate_Patient_Value]    Script Date: 27/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Aggregate_Patient_Value
--  Author :  AIH
--  Date   :  27/09/2026
--
--  WHAT A PATIENT IS WORTH OVER A ROLLING 36 MONTHS -- one row per patient.
--
--  ==> IT REPLACES "LIFETIME VALUE", WHICH WAS WRONG TWICE OVER. <==
--
--  1. IT COUNTED NO PLAN INCOME. The measure was SUM('List Patients'[Total Invoiced]), and a
--     membership patient's monthly fee is not an invoice. On the live practice:
--
--         cohort          patients   avg invoiced   avg capitation   avg TOTAL
--         plan patient       1,416           737            2,139       2,876
--         private            4,048         1,390               24       1,414
--         NHS                1,571           164                1         165
--
--     So the practice's most valuable cohort showed as worth HALF a private patient, with
--     74% of their value invisible. For a figure whose whole job is "who would I mind
--     losing", it ranked the two largest cohorts the wrong way round.
--
--  2. IT WAS NEVER A LIFETIME. Dentally holds nothing before a practice migrates onto it --
--     the live practice's own patient_stats total is SMALLER than what the warehouse has
--     loaded since go-live, so there is no longer history being truncated; it does not exist.
--     "Lifetime" therefore meant 5.7 years for one customer and six months for the next, and
--     was never comparable between practices or over time.
--
--  A ROLLING 36 MONTHS is computable for every practice, means the same thing for all of
--  them, and is long enough to cover three recall cycles. A practice live for less than that
--  gets what it has -- but the label no longer overclaims.
--
--  Attendance is carried alongside deliberately, NOT instead. The two answer different
--  questions: a plan patient attending six-monthly hygiene is loyal and low-margin, a private
--  patient with one 2,000 crown a year is the reverse. High value + low attendance is a
--  different retention risk from high attendance + low value, and collapsing them to one
--  number loses exactly the distinction the report exists to draw.
--
--  Pattern: GOLD_AGG, DROP/CREATE full rebuild -- it reads other Gold facts and is wholly
--  derived, so there is nothing an incremental load would protect.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Aggregate_Patient_Value]
GO
CREATE TABLE [Gold].[Aggregate_Patient_Value](
    [pk_Patient_Value]        [bigint]        NOT NULL,
    [Tenant_ID]               [int]           NOT NULL,
    [fk_Patient]              [bigint]        NOT NULL,
    [fk_Practice_Site]        [bigint]            NULL,
    [Window_Months]           [smallint]      NOT NULL,   -- 36; stated so the number is readable
    [Window_From]             [date]          NOT NULL,
    [Value_Invoiced]          [decimal](18,4)     NULL,
    [Value_Capitation]        [decimal](18,4)     NULL,   -- the half "lifetime value" omitted
    [Value_Total]             [decimal](18,4)     NULL,
    [Appointments_Attended]   [int]               NULL,   -- engagement, not worth
    [Last_Attended_Date]      [date]              NULL,
    [Value_Per_Year]          [decimal](18,4)     NULL,   -- comparable across part-windows
    [DW_Created_At]           [datetime2](3)  NOT NULL,
    [DW_Updated_At]           [datetime2](3)  NOT NULL
)
GO
