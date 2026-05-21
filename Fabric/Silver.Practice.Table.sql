/****** Object:  Table [Silver].[Practice]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Practice]
GO
CREATE TABLE [Silver].[Practice](
	[Tenant_ID] [int] NOT NULL,
	[Practice_ID] [VARCHAR](50) NOT NULL,
	[Practice_Name] [VARCHAR](255) NULL,
	[Email_Address] [VARCHAR](255) NULL,
	[Phone_Number] [VARCHAR](50) NULL,
	[Address_Line_1] [VARCHAR](255) NULL,
	[Address_Line_2] [VARCHAR](255) NULL,
	[Town] [VARCHAR](100) NULL,
	[County] [VARCHAR](100) NULL,
	[Postcode] [VARCHAR](20) NULL,
	[Country] [VARCHAR](100) NULL,
	[NHS] [int] NULL,
	[Time_Zone] [VARCHAR](50) NULL,
	[Website] [VARCHAR](200) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
