/****** Object:  Table [Config].[Xero_Site_Map]  ******/
-- Per-tenant map of a Xero tracking (Category, Option) to a Dentally Practice Site,
-- for orgs that host several sites in one Xero and split them by tracking category.
-- Populated per client from Silver.Xero_Tracking; empty by default (orgs fall back to
-- Xero_Orgs.Default_Site_ID). Site_ID is the Dim_Practice_Sites business key.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Config].[Xero_Site_Map]
GO
CREATE TABLE [Config].[Xero_Site_Map](
	[Tenant_ID] [int] NOT NULL,
	[Category_Name] [varchar](255) NOT NULL,
	[Option_Name] [varchar](255) NOT NULL,
	[Site_ID] [varchar](50) NOT NULL
)
GO
