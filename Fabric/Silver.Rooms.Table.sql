/****** Object:  Table [Silver].[Rooms]    Script Date: 19/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Rooms]
GO
CREATE TABLE [Silver].[Rooms](
	[Tenant_ID] [int] NOT NULL,
	[Room_ID] [VARCHAR](50) NOT NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[Name] [VARCHAR](255) NULL,
	[Colour] [VARCHAR](100) NULL,
	[Calendar_Position] [int] NULL,
	[Created_At] [VARCHAR](50) NULL,
	[Updated_At] [VARCHAR](50) NULL,
	[Practice_ID] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
