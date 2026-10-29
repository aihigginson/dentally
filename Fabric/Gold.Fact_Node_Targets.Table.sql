/****** Object:  Table [Gold].[Fact_Node_Targets]    Script Date: 29/10/2026 ******/
--------------------------------------------------------------------
--  Gold.Fact_Node_Targets -- the target grid, keyed on WHAT THE USER PICKED.
--
--  One row per (client, selection, role, FY, metric): the annual target in force, whether
--  somebody typed it or it was derived. Built by Gold.usp_Load_Fact_Node_Targets; Input.Targets
--  stays sparse and holds only what was typed.
--
--  ==> THE COLUMNS ARE THE THINGS BEING SELECTED, NOT A WAY OF ADDRESSING THEM. <== This table
--  used to carry Level_Type ('Area') + Level_Key ('7') + Tenant_ID, and a reader could not tell
--  what any row meant without joining three hierarchy tables. Worse, the keys collided -- Group
--  '11' and Practice '11', Region '5' and Area '5' -- and the Site key held the Dentally business
--  key while every report filters the warehouse surrogate, so Site targets matched nothing at all.
--
--  [Selection] is now the EXACT string the hierarchy drop-down displays, indent markers included:
--
--      Skeleton Group                 <- the client, depth 0, no indent
--      <FIG><FIG>- North              <- depth 1
--      <FIG>x4- Manchester            <- depth 2
--      <FIG>x6- Skeleton Alpha        <- depth 3
--
--  where <FIG> is U+2007 FIGURE SPACE and the dash is U+2013 EN DASH, matching
--  index.html: ' '.repeat(depth * 2) + '– ' + label. So the app filters with
--  [Selection] = <the value the user chose>, and nothing has to be resolved, parsed or joined.
--
--  ==> WHICH IS WHY THERE IS NO LEVEL COLUMN. <== The table does not need to know that one row is
--  a region and another an area: it matches the text. And the text is unique without a level,
--  because the indent is part of it -- client 11 has a PRACTICE and a SITE both called
--  "Demonstration Practice", and they differ here by six figure spaces against eight. The
--  hierarchy that produced these strings lives in Input.Client_Region / _Area / Site_Area and is
--  used inside the loader to roll values up and down; it is then thrown away.
--
--  [Role] is 'All Roles' for the practice-wide figure, or the practitioner's Custom Role
--  ('Principal', 'Hygienist', ...). It was called Target_Level and the practice-wide value was
--  spelt 'Practice', which read as a hierarchy level in a column that is nothing of the kind.
--
--  ==> CLIENT-KEYED, AND DELIBERATELY SO. <== A target above a practice spans tenants. Giving it
--  a Tenant_ID would mean duplicating the row per tenant -- inviting a SUM that double counts --
--  or parking it on the -1 sentinel, which the RLS escape would then show to every other client.
--  So this is the first fact keyed on the client, and it needs its own RLS rule reading
--  'Application Users'[Client ID] rather than the shared [Tenant ID] one.
--  Check_RLS_Expression.ps1 will report it as the odd one out; that is correct, not a fault.
--
--  Is_Entered: 1 = somebody typed this figure, 0 = derived. The targets screen greys the derived
--  ones, and it is also the only way to tell a deliberate zero from an absent one after the fact.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP TABLE IF EXISTS [Gold].[Fact_Node_Targets]
GO
CREATE TABLE [Gold].[Fact_Node_Targets] (
    [pk_Node_Target]  BIGINT          NOT NULL,
    [Client_ID]       INT             NOT NULL,
    [Selection]       VARCHAR(200)    NOT NULL,   -- the drop-down text, indent included
    [Role]            VARCHAR(50)     NOT NULL,   -- 'All Roles', or the Custom Role
    [Metric]          VARCHAR(100)    NOT NULL,   -- the key the measures filter on
    [Metric_Name]     VARCHAR(200)    NULL,       -- the display name, so the grid reads
    [FY]              INT             NOT NULL,
    [Target_Value]    DECIMAL(18,4)   NULL,
    [Is_Entered]      BIT             NOT NULL,   -- 1 = typed, 0 = rolled up or down
    [DW_Created_At]   DATETIME2(6)    NOT NULL
)
GO
