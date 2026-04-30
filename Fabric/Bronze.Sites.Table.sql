/****** Object:  Table [Bronze].[Sites]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Sites]
GO
CREATE TABLE [Bronze].[Sites](
	[Site_ID] [VARCHAR](255) NULL,
	[Active] [decimal](18, 4) NULL,
	[Address_Line_1] [VARCHAR](255) NULL,
	[Address_Line_2] [VARCHAR](255) NULL,
	[Default_Payment_Plan_ID] [decimal](18, 4) NULL,
	[Logo_Url] [VARCHAR](255) NULL,
	[Name] [VARCHAR](255) NULL,
	[Nickname] [decimal](18, 4) NULL,
	[Phone_Number] [VARCHAR](255) NULL,
	[Postcode] [VARCHAR](255) NULL,
	[Practice_ID] [VARCHAR](255) NULL,
	[Town] [VARCHAR](255) NULL,
	[Website] [VARCHAR](255) NULL,
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
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
