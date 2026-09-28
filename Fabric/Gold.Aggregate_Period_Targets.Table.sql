/****** Object:  Table [Gold].[Aggregate_Period_Targets]    Script Date: 28/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Aggregate_Period_Targets
--  Author :  AIH
--  Date   :  28/09/2026
--
--  THE TARGET FOR A PERIOD, AT THE GRAIN THE PRODUCT ACTUALLY ASKS FOR.
--
--  ==> THE MODEL WAS RE-AGGREGATING 243,252 DAILY ROWS PER TILE, EVERY RENDER. <== Every target
--  and variance measure resolved its number by scanning Gold.Fact_Daily_Targets across the
--  selected period. The Home page carries 28 tiles, each with a value, a target, a vs-target and
--  a colour, so ~84 of those scans happen on one render -- and again on every bookmark switch.
--
--  It was measured rather than guessed. The same report with the target measures removed renders
--  INSTANTLY on the same F4; with them it takes ~45 seconds, after the model is already resident
--  and with RLS bypassed. Desktop was always instant, which is what hid it for so long: a laptop
--  simply has more query compute than an F4 and absorbed the waste.
--
--  ==> THE PERIOD IS ALWAYS A NAMED GROUPING, NEVER AN ARBITRARY RANGE. <== The app filters
--  'List Date Grouping'[Date Grouping] to exactly one value -- 'Last 3 Months', 'Last 12 Months'
--  or a financial year. That is what makes this table possible: the target can be computed once
--  per grouping instead of derived from days on every query. 1,296 rows replace 243,252, and the
--  measure becomes a lookup with no date scan at all.
--
--  ==> THE AGGREGATION MIRRORS WHAT THE DAX DID, PER TARGET TYPE. <== Getting this wrong would
--  move every number on the board, so it follows Config.Metric_Definitions.Target_Type exactly:
--
--    cumulative     SUM(Daily_Target_Value) over the grouping's dates -- accumulates, so a
--                   part-period target is the prorated share. Matches tEffRunRate/tCumFTE.
--    rate           MAX(Annual_Target_Value) -- a ratio is period-independent; the target is a
--                   threshold that does not accumulate. Matches tRate/tEff.
--    point_in_time  MAX(Annual_Target_Value) -- a snapshot compared against a fixed threshold;
--                   summing days would be meaningless.
--
--  Variance is MAX: it is a band per (metric, level), not a quantity, so it never accumulates.
--
--  WHAT DELIBERATELY STAYS IN DAX: the FTE multiplier and the Target_Level choice. Both depend
--  on which practitioners are selected at query time, so neither can be precomputed -- but both
--  are now cheap filters on 1,296 rows rather than riders on a 243k-row scan.
--
--  Pattern: GOLD_AGG, DROP/CREATE full rebuild -- wholly derived from Fact_Daily_Targets and
--  Dim_Date_Grouping, so there is nothing an incremental load would protect.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Aggregate_Period_Targets]
GO
CREATE TABLE [Gold].[Aggregate_Period_Targets](
    [pk_Period_Target]   [bigint]        NOT NULL,
    [Tenant_ID]          [int]           NOT NULL,
    [Date_Grouping]      [varchar](30)   NOT NULL,   -- joins 'List Date Grouping'[Date Grouping]
    [Metric]             [varchar](100)  NOT NULL,
    [Target_Level]       [varchar](100)  NOT NULL,   -- 'Practice' or a Custom_Role
    [Target_Type]        [varchar](20)       NULL,   -- carried so the rule is readable in the data
    [Target_Value]       [decimal](18,4)     NULL,
    [Variance]           [decimal](18,4)     NULL,
    [Working_Days]       [int]               NULL,   -- days behind a cumulative target
    [DW_Created_At]      [datetime2](6)  NOT NULL,
    [DW_Updated_At]      [datetime2](6)  NOT NULL
)
GO
