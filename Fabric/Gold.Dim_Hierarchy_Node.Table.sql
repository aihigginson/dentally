/****** Object:  Table [Gold].[Dim_Hierarchy_Node]    Script Date: 29/10/2026 ******/
--------------------------------------------------------------------
--  Gold.Dim_Hierarchy_Node -- what each drop-down selection actually covers.
--
--  One row per (selection, site). The hierarchy drop-down offers a flat, indented list of
--  selections; this says which practice sites each one resolves to, which is the only thing
--  anybody needs to know about it.
--
--  ==> ONE DEFINITION OF THE SELECTION STRING, AND THIS IS IT. <== The same text is needed in
--  three places -- the drop-down the user picks from, Gold.Fact_Node_Targets, and the NHS branch
--  of the period loader -- and Fabric's collation is binary, so a single wrong character makes a
--  filter match nothing, silently. Rather than render it three times, Gold.usp_Load_Fact_Node_Targets
--  builds it once, here, and everything else reads it. /api/filters should serve the drop-down
--  from this table for the same reason: a label it renders itself can drift from the one stored.
--
--  Depth is kept so a reader can sort the list back into tree order. [Level] says what kind of
--  thing a node is, and it is here for one question the site sets cannot answer: WHICH SELECTION
--  IS THIS PRACTICE? A region holding a single practice covers exactly that one tenant, so
--  "the shallowest node covering one tenant" picks the region -- and an NHS contract target
--  attached there is invisible when the practice itself is selected.
--
--  ==> THE LEVEL LIVES HERE AND NOWHERE DOWNSTREAM. <== Gold.Fact_Node_Targets and
--  Gold.Aggregate_Period_Targets carry no level: they match the selection text, and the indent
--  makes it unique. This is the one table whose job IS to describe the hierarchy.
--
--  Client-keyed, like the targets it exists to serve, so it needs an RLS rule on
--  'Application Users'[Client ID] rather than the shared [Tenant ID] one.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP TABLE IF EXISTS [Gold].[Dim_Hierarchy_Node]
GO
CREATE TABLE [Gold].[Dim_Hierarchy_Node] (
    [pk_Hierarchy_Node]  BIGINT        NOT NULL,
    [Client_ID]          INT           NOT NULL,
    [Selection]          VARCHAR(200)  NOT NULL,   -- the drop-down text, indent included
    [Depth]              INT           NOT NULL,   -- 0 = the client; for sorting only
    [Level]              VARCHAR(10)   NOT NULL,   -- Client|Region|Area|Practice|Site
    [fk_Practice_Site]   BIGINT        NOT NULL,   -- a site this selection resolves to
    [Tenant_ID]          INT           NOT NULL,   -- that site's practice
    [DW_Created_At]      DATETIME2(6)  NOT NULL
)
GO
