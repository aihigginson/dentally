/****** Object:  Table [Silver].[Xero_Orgs]  ******/
-- Typed connected-org registry: Xero org -> Dentally Tenant_ID + default Practice Site.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Xero_Orgs]
GO
CREATE TABLE [Silver].[Xero_Orgs](
	[Tenant_ID] [int] NULL,
	[Xero_Tenant_ID] [varchar](100) NULL,
	[Tenant_Name] [varchar](255) NULL,
	[Default_Site_ID] [varchar](50) NULL,
	[DW_Loaded_At] [datetime2](3) NULL,
	[DW_Updated_At] [datetime2](3) NULL
)
GO
