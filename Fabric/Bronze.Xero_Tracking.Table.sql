/****** Object:  Table [Bronze].[Xero_Tracking]  ******/
-- Xero tracking categories + their options, per org. Reference data used to build the
-- (Category, Option) -> Practice Site map (Config.Xero_Site_Map). Landed by xero_land.py.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Xero_Tracking]
GO
CREATE TABLE [Bronze].[Xero_Tracking](
	[Tenant_ID] [int] NULL,
	[Xero_Tenant_ID] [varchar](100) NULL,
	[Tracking_Category_ID] [varchar](100) NULL,
	[Category_Name] [varchar](255) NULL,
	[Category_Status] [varchar](50) NULL,
	[Tracking_Option_ID] [varchar](100) NULL,
	[Option_Name] [varchar](255) NULL,
	[Option_Status] [varchar](50) NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
