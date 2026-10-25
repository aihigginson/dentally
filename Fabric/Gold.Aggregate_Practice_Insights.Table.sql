/****** Object:  Table [Gold].[Aggregate_Practice_Insights] ******/
--------------------------------------------------------------------
--  Table  :  Gold.Aggregate_Practice_Insights
--  Author :  AIH
--  Date   :  21/10/2026
--
--  THE THREE THINGS GETTING WORSE AND THE THREE GETTING BETTER, PER PRACTICE, PER WEEK.
--
--  The product knows a practice's metrics, their direction of good, and their own targets.
--  What it never told them was which of those to look at FIRST. This is that answer, computed
--  once a night rather than asked for.
--
--  ==> MOVEMENT IS THE SIGNAL. DISTANCE FROM TARGET IS NOT. <== The first prototype ranked on
--  how far each metric sat from its target and returned Outstanding Invoices, Open Courses Value
--  and Open Courses -- every one an enormous multiple of target, every one already known, and
--  all three previously confirmed as WIP that is CORRECTLY high. Distance from target measures
--  how long a problem has existed. It is wallpaper. What a practice can act on is what just
--  changed, so the ranking is period-over-period movement and the target is carried only as
--  context.
--
--  ==> FOUR WEEKS AGAINST FOUR WEEKS, STEPPED WEEKLY. <== Measured on the live tenant:
--
--     week-on-week   Deposit Ratio read 4.0 -> 6.8 -> 12.5 -> 11.9 -> 30.9 -> 9.9%, flipping
--                    between "going well" and "needs attention" on consecutive weeks. Short
--                    Notice Cancellations did the same. That is a small denominator resampling,
--                    not news, and a practice told opposite things each week stops believing
--                    any of it.
--     4wk vs 4wk     Short Notice Cancellations read WATCH for four consecutive runs at
--                    +27/+26/+52/+56%, and Average Plan Value GOOD at +22/+39/+55/+40%. Same
--                    story each week, strengthening.
--
--  Months were rejected before weeks: they are unequal lengths, so a count metric would fall
--  every February for no reason worth reporting.
--
--  ==> COUNTS ARE PER WORKING DAY, RATES ARE NOT. <== A bank holiday makes a four-day week and
--  drops a count by a fifth on nothing at all. A rate divides that out by construction; a count
--  or a cumulative total does not, so those are normalised on Dim_Date.Is_Working_Day_England
--  before the two windows are compared.
--
--  Narrative is written by a language model AFTER this table is built -- the app fills it on the
--  nightly hook. It is NULLABLE on purpose: the ranking is the product and must stand on its own
--  if the model is unavailable, slow, or switched off. Nothing downstream may assume it is set.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP TABLE IF EXISTS [Gold].[Aggregate_Practice_Insights]
GO

CREATE TABLE [Gold].[Aggregate_Practice_Insights](
    [pk_Insight]            [bigint]        NOT NULL,
    [Tenant_ID]             [int]           NOT NULL,
    [Week_Commencing_Date]  [date]          NOT NULL,   -- the latest COMPLETE week
    [Direction]             [varchar](10)   NOT NULL,   -- 'Watch' | 'Good'
    [Rank_In_Direction]     [int]           NOT NULL,   -- 1, 2, 3
    [Metric]                [varchar](100)  NOT NULL,
    [Display_Name]          [varchar](200)  NULL,
    [Section]               [varchar](50)   NULL,
    [Format_Type]           [varchar](20)   NULL,       -- percent | currency | count
    [Per_Working_Day]       [bit]           NOT NULL,   -- was the value normalised?
    [Value_Now]             [decimal](18,4) NULL,
    [Value_Before]          [decimal](18,4) NULL,
    [Relative_Change]       [decimal](18,6) NULL,       -- signed, as a fraction
    [Target_Value]          [decimal](18,4) NULL,       -- context only, may be NULL
    -- ==> THE SAME MOVE A YEAR AGO, SO SEASONAL IS NOT MISTAKEN FOR NEW. <== Average Plan
    -- Value climbs every autumn as patients return from holiday and book treatment rather
    -- than check-ups. Reporting that as a win each September would cost the panel its
    -- credibility. NULL where there is no comparable year.
    [Last_Year_Change]      [decimal](18,6) NULL,
    [Narrative]             [varchar](600)  NULL,       -- written later, never required
    [DW_Created_At]         [datetime2](6)  NOT NULL,
    [DW_Updated_At]         [datetime2](6)  NOT NULL
)
GO
