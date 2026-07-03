/****** Object:  Table [Bronze].[Xero_Orgs]  ******/
-- One row per connected Xero organisation: the Dentally Tenant_ID it maps to and the
-- default Practice Site used when a line has no site tracking (the whole-org site for a
-- single-site practice). Landed by API/xero_land.py.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Xero_Orgs]
GO
CREATE TABLE [Bronze].[Xero_Orgs](
	[Tenant_ID] [int] NULL,
	[Xero_Tenant_ID] [varchar](100) NULL,
	[Tenant_Name] [varchar](255) NULL,
	[Default_Site_ID] [varchar](50) NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
