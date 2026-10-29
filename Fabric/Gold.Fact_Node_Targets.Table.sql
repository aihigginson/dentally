/****** Object:  Table [Gold].[Fact_Node_Targets]    Script Date: 29/10/2026 ******/
--------------------------------------------------------------------
--  Gold.Fact_Node_Targets -- the target grid, exploded across the client hierarchy.
--
--  One row per (node, FY, metric, role): what the target IS at that node, whether somebody typed
--  it or it was derived by rolling up from the children or down from the parent. Built by
--  Gold.usp_Load_Fact_Node_Targets; Input.Targets stays sparse and holds only what was typed.
--
--  ==> CLIENT-KEYED, AND DELIBERATELY SO. <== A Region or Area target spans tenants. Giving it a
--  Tenant_ID would mean duplicating the row per tenant -- and inviting a SUM that double counts
--  -- or parking it on the -1 sentinel, which the RLS escape would then show to every other
--  client. Tenant_ID is present but NULL above Practice, because that is the truth.
--
--  This is the first fact keyed on the client rather than the tenant, so it needs its own RLS
--  rule reading 'Application Users'[Client ID] rather than the shared [Tenant ID] one.
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
    [Level_Type]      VARCHAR(10)     NOT NULL,   -- Group | Region | Area | Practice | Site
    [Level_Key]       VARCHAR(64)     NOT NULL,   -- int for Region/Area/Practice, string for Site
    [Tenant_ID]       INT             NULL,       -- Practice and Site only; NULL above them
    [FY]              INT             NOT NULL,
    [Metric]          VARCHAR(100)    NOT NULL,
    [Target_Level]    VARCHAR(50)     NOT NULL,   -- the ROLE, or 'Practice' for all of them
    [Target_Value]    DECIMAL(18,4)   NULL,
    [Is_Entered]      BIT             NOT NULL,   -- 1 = typed, 0 = rolled up or down
    [DW_Created_At]   DATETIME2(6)    NOT NULL
)
GO
