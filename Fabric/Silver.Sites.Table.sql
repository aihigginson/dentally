/****** Object:  Table [Silver].[Sites]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Sites]
GO
CREATE TABLE [Silver].[Sites](
	[Site_Id] [VARCHAR](50) NOT NULL,
	[Practice_Id] [VARCHAR](50) NOT NULL,
	[Name] [VARCHAR](255) NULL,
	[active] [int] NULL,
	[address_line_1] [VARCHAR](255) NULL,
	[address_line_2] [VARCHAR](255) NULL,
	[town] [VARCHAR](255) NULL,
	[postcode] [VARCHAR](255) NULL,
	[phone_number] [VARCHAR](255) NULL,
	[website] [VARCHAR](255) NULL,
	[logo_url] [VARCHAR](255) NULL,
	[default_payment_plan_id] [VARCHAR](255) NULL,
	[monday_open] [VARCHAR](255) NULL,
	[monday_close] [VARCHAR](255) NULL,
	[tuesday_open] [VARCHAR](255) NULL,
	[tuesday_close] [VARCHAR](255) NULL,
	[wednesday_open] [VARCHAR](255) NULL,
	[wednesday_close] [VARCHAR](255) NULL,
	[thursday_open] [VARCHAR](255) NULL,
	[thursday_close] [VARCHAR](255) NULL,
	[friday_open] [VARCHAR](255) NULL,
	[friday_close] [VARCHAR](255) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
