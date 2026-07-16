-- Config.Module_Pricing
-- Vendor-set system default price per billable module (the 10 Access_* flags). One row per module.
-- Effective price for a tenant = COALESCE(Config.Tenant_Module_Pricing override, this default).
-- IDEMPOTENT CREATE so pricing survives redeploys; the .Data.sql reseeds the catalog (vendor-managed).
IF OBJECT_ID('Config.Module_Pricing') IS NULL
CREATE TABLE [Config].[Module_Pricing] (
    [Module_Key]    [varchar](50)  NOT NULL,   -- 'Home','Revenue','Patient','Schedule','Clinical',
                                               -- 'NHS','Day_Book','Finance','My_Data','Marketing'
    [Display_Name]  [varchar](100) NOT NULL,
    [Monthly_Price] [decimal](9,2) NOT NULL,   -- vendor system default (GBP/month)
    [Display_Order] [int]          NULL,
    [Is_Active]     [bit]          NOT NULL
);
GO
