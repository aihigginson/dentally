-- Config.Tenant_Module_Pricing
-- Per-tenant price override for a module (vendor-managed; NOT editable by the practice). Sparse:
-- only rows where a tenant's price differs from the Config.Module_Pricing system default.
-- Effective price = COALESCE(this override, Config.Module_Pricing.Monthly_Price).
-- IDEMPOTENT CREATE so overrides survive redeploys (they are data, not destructively reseeded).
IF OBJECT_ID('Config.Tenant_Module_Pricing') IS NULL
CREATE TABLE [Config].[Tenant_Module_Pricing] (
    [Tenant_ID]     [int]          NOT NULL,
    [Module_Key]    [varchar](50)  NOT NULL,
    [Monthly_Price] [decimal](9,2) NOT NULL,
    [Updated_At]    [datetime2](3) NULL,
    [Updated_By]    [varchar](255) NULL
);
GO
