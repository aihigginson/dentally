/****** Object:  Table [Gold].[Fact_Plan_Spell]    Script Date: 27/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Fact_Plan_Spell
--  Author :  AIH
--  Date   :  27/09/2026
--
--  ONE ROW PER PATIENT PER CONTINUOUS MEMBERSHIP SPELL -- what a plan patient actually is.
--
--  Capitation had no such record. It existed only as 2.6m exploded member-day rows in
--  Fact_Revenue, so "when was this patient a member, on what plan, at what rate" could only be
--  answered by aggregating a fact back up. This is that answer, stored once.
--
--  ==> THE SPELL IS EVIDENCED, THE BILLING IS BOUNDED -- AND THEY ARE NOT THE SAME. <== The
--  spell runs from the first to the last month with membership evidence. Billing runs only from
--  the tenant's Cutover_Date (Dentally holds imported historical plans back to 2010, which never
--  produced revenue for the practice on our watch) and only up to today. A patient can therefore
--  have a spell starting years before the first penny is attributed to them, and both facts
--  matter: the spell is how long they have been a member, the billed window is what we can
--  legitimately report as income. Carrying both stops the next person conflating them.
--
--  Evidence_Months is the count of DISTINCT months with a qualifying course, not the length of
--  the spell. A patient with 14 months of evidence across a 30-month spell has gaps that the
--  spell deliberately bridges -- missing an exam does not cancel a membership. Keeping the two
--  numbers side by side is what makes that bridging visible rather than assumed.
--
--  ==> HOW A SPELL ENDS DEPENDS ON WHETHER THEY ARE STILL ON THE PLAN, AND THE TWO CASES ARE
--  NOT SYMMETRICAL. <== Still on a rated plan and active: today. The practice needs that marker
--  in Dentally to treat them without charging, so somebody maintains it. It is NOT evidence of
--  payment -- a direct debit can have failed yesterday with the patient still flagged active and
--  the dentist not getting paid. This table is membership, not collection.
--
--  No longer on a plan: the last attended free exam, which is the last evidence the membership
--  existed. It is a date, not a month end. Before V190 the spell ran to the end of that month,
--  so a member last seen on 3 March carried capitation to 31 March -- four weeks of fees after
--  the evidence ran out.
--
--  Is_Estimated_Plan = 1 means the plan was attributed via the Is_Default fallback because
--  Dentally no longer records the patient's original plan -- a lapsed member. The rate is then
--  the default plan's, not theirs, so these rows are an estimate and must stay distinguishable.
--
--  Pattern: rebuilt in full by Gold.usp_Load_Fact_Revenue, in the same pass and from the same
--  CTE that produces the capitation rows. It is not its own chain node on purpose: a node of its
--  own would have to sit below GOLD_FACT_REVENUE, pushing revenue to level 5 and colliding with
--  the four aggregates that already depend on it at level 5. Same procedure means the spell and
--  the revenue derived from it can never disagree.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Plan_Spell]
GO
CREATE TABLE [Gold].[Fact_Plan_Spell](
    [pk_Plan_Spell]       [bigint]        NOT NULL,
    [Tenant_ID]           [int]           NOT NULL,
    [fk_Patient]          [bigint]        NOT NULL,
    [fk_Payment_Plan]     [bigint]        NOT NULL,
    [fk_Practitioner]     [bigint]        NOT NULL,
    [fk_Practice_Site]    [bigint]        NOT NULL,
    [Spell_Start_Date]    [date]          NOT NULL,   -- first month with membership evidence
    [Spell_End_Date]      [date]          NOT NULL,   -- a DATE: today, or the last free exam
    [Spell_Months]        [int]               NULL,
    [Evidence_Months]     [int]               NULL,   -- months with a course; <= Spell_Months
    [Is_Open]             [bit]           NOT NULL,   -- still a member this month
    [Is_Estimated_Plan]   [bit]           NOT NULL,   -- plan attributed by the default fallback
    [Billed_From_Date]    [date]              NULL,   -- bounded by the tenant's Cutover_Date
    [Billed_To_Date]      [date]              NULL,
    [Billed_Segments]     [int]               NULL,   -- week-within-month rows in Fact_Revenue
    [Spell_Value]         [decimal](18,6)     NULL,   -- capitation attributed across the spell
    [DW_Created_At]       [datetime2](6)  NOT NULL,
    [DW_Updated_At]       [datetime2](6)  NOT NULL
)
GO
