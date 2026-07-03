/****** Object:  Table [Silver].[Xero_Tracking]  ******/
-- Typed Xero tracking categories + options (site-split reference data).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Xero_Tracking]
GO
CREATE TABLE [Silver].[Xero_Tracking](
	[Tenant_ID] [int] NULL,
	[Xero_Tenant_ID] [varchar](100) NULL,
	[Tracking_Category_ID] [varchar](100) NULL,
	[Category_Name] [varchar](255) NULL,
	[Category_Status] [varchar](50) NULL,
	[Tracking_Option_ID] [varchar](100) NULL,
	[Option_Name] [varchar](255) NULL,
	[Option_Status] [varchar](50) NULL,
	[DW_Loaded_At] [datetime2](3) NULL,
	[DW_Updated_At] [datetime2](3) NULL
)
GO
