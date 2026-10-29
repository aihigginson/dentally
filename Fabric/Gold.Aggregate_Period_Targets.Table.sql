/****** Object:  Table [Gold].[Aggregate_Period_Targets]    Script Date: 29/10/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Aggregate_Period_Targets
--  Author :  AIH
--  Date   :  28/09/2026
--  History:
--    *01  28/09/2026  AIH  Precompute the target per (Date_Grouping, Metric, Target_Level).
--    *02  29/10/2026  AIH  Built from Gold.Fact_Node_Targets; the daily explosion is gone.
--    *03  29/10/2026  AIH  Keyed on the DROP-DOWN TEXT. Tenant_ID/Level_Type/Level_Key gone.
--
--  THE TARGET FOR A PERIOD, KEYED ON WHAT THE USER PICKED.
--
--  ==> THE COLUMNS ARE THE THINGS BEING SELECTED. <== A row reads "client 20, '<indent>- Skeleton
--  Alpha', All Roles, total_revenue, Last 12 Months, 1906596" -- the period selector's text, the
--  hierarchy selector's text, the role selector's text, then the number. So a measure or a report
--  filter is an equality against the value the user chose, with nothing to resolve or join.
--  See the header of Gold.Fact_Node_Targets for why there is no level column.
--
--  ==> TENANT_ID IS AN ACCESS KEY HERE, NOT AN ATTRIBUTION KEY. <== Read that again before
--  joining it to anything. A row for 'Skeleton Group' or '- North' covers several practices and
--  has no natural tenant, so it carries MIN(Tenant_ID) of the practices beneath it purely so the
--  blanket RLS rule -- [Tenant ID] IN (the caller's tenants) -- admits it for that client and
--  nobody else.
--
--  It is therefore a LIE about attribution, and a more dangerous one than the -1 sentinel it
--  replaces: -1 is self-evidently not a practice, whereas 21 is. Group or GROUP BY these targets
--  on Tenant_ID and Skeleton Alpha is credited with the whole group's figure -- a plausible wrong
--  number, which is the kind that survives review. Attribution is [Selection], always. The column
--  is hidden in the model for the same reason.
--
--  Safe only because the table is a full DELETE + INSERT rebuild that runs after the AppDB sync
--  (META_SYNC_INPUT -> GOLD_FACT_NODE_TARGETS), so the stamp cannot outlive the membership it
--  was derived from. A guard at the end of the loader asserts exactly that.
--
--  ==> THE PERIOD IS ALWAYS A NAMED GROUPING, NEVER AN ARBITRARY RANGE. <== The app filters
--  'List Date Grouping'[Date Grouping] to exactly one value -- 'Last 3 Months', 'Last 12 Months'
--  or a financial year -- which is what makes this table possible at all: the target is computed
--  once per grouping instead of derived from days on every query.
--
--  The original win still stands and is worth not undoing. Every target and variance measure used
--  to resolve its number by scanning Gold.Fact_Daily_Targets (243,252 rows) across the selected
--  period. The Home page carries 28 tiles, each with a value, a target, a vs-target and a colour,
--  so ~84 of those scans happened per render, and again on every bookmark switch. Measured, not
--  guessed: the same report with the target measures removed rendered INSTANTLY on the same F4;
--  with them, ~45 seconds, after the model was resident and with RLS bypassed. Desktop was always
--  instant, which is what hid it -- a laptop has more query compute than an F4 and absorbed it.
--
--  ==> THE AGGREGATION FOLLOWS Config.Metric_Definitions.Target_Type. <==
--
--    cumulative     the share of each financial year the window covers, SUMMED over the years it
--                   touches. A rolling window straddles the client's year end and the two years
--                   can carry different targets -- collapsing it to one applied the later year's
--                   figure to the whole window and dropped metrics targeted only in the earlier.
--    rate           the strictest annual across those years -- a ratio is period-independent.
--    point_in_time  likewise: a snapshot against a fixed threshold; summing days is meaningless.
--
--  Variance is a band per (metric, role), not a quantity, so it never accumulates.
--
--  Is_Entered is carried through so a report can show a derived target differently from one
--  somebody actually committed to.
--
--  WHAT DELIBERATELY STAYS IN DAX: the FTE multiplier and the role choice. Both depend on which
--  practitioners are selected at query time, so neither can be precomputed.
--
--  Pattern: GOLD_AGG, DROP/CREATE full rebuild -- wholly derived from Gold.Fact_Node_Targets and
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
    [Client_ID]          [int]           NOT NULL,
    [Tenant_ID]          [int]           NOT NULL,   -- ACCESS KEY ONLY -- see the header
    [Selection]          [varchar](200)  NOT NULL,   -- the hierarchy drop-down text
    [Role]               [varchar](50)   NOT NULL,   -- 'All Roles', or the Custom Role
    [Metric]             [varchar](100)  NOT NULL,   -- the key the measures filter on
    [Metric_Name]        [varchar](200)      NULL,   -- the display name, so the grid reads
    [Date_Grouping]      [varchar](30)   NOT NULL,   -- joins 'List Date Grouping'[Date Grouping]
    [Target_Type]        [varchar](20)       NULL,   -- carried so the rule is readable in the data
    [Target_Value]       [decimal](18,4)     NULL,
    [Variance]           [decimal](18,4)     NULL,
    [Working_Days]       [int]               NULL,   -- days behind a cumulative target
    [Is_Entered]         [bit]               NULL,   -- 1 = somebody typed it, 0 = derived
    [DW_Created_At]      [datetime2](6)  NOT NULL,
    [DW_Updated_At]      [datetime2](6)  NOT NULL
)
GO
