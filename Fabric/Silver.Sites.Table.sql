/****** Object:  Table [Silver].[Sites]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Sites]
GO
CREATE TABLE [Silver].[Sites](
	[Tenant_ID] [int] NOT NULL,
	[Site_ID] [VARCHAR](50) NOT NULL,
	[Practice_ID] [VARCHAR](50) NOT NULL,
	[Name] [VARCHAR](255) NULL,
	[Nickname] [VARCHAR](255) NULL,
	[Active] [int] NULL,
	[Address_Line_1] [VARCHAR](255) NULL,
	[Address_Line_2] [VARCHAR](255) NULL,
	[Town] [VARCHAR](255) NULL,
	[Postcode] [VARCHAR](255) NULL,
	[Phone_Number] [VARCHAR](255) NULL,
	[Website] [VARCHAR](255) NULL,
	[Logo_URL] [VARCHAR](255) NULL,
	[Default_Payment_Plan_ID] [VARCHAR](255) NULL,
	[Monday_Open] [VARCHAR](255) NULL,
	[Monday_Close] [VARCHAR](255) NULL,
	[Tuesday_Open] [VARCHAR](255) NULL,
	[Tuesday_Close] [VARCHAR](255) NULL,
	[Wednesday_Open] [VARCHAR](255) NULL,
	[Wednesday_Close] [VARCHAR](255) NULL,
	[Thursday_Open] [VARCHAR](255) NULL,
	[Thursday_Close] [VARCHAR](255) NULL,
	[Friday_Open] [VARCHAR](255) NULL,
	[Friday_Close] [VARCHAR](255) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
