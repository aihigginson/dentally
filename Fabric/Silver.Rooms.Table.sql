/****** Object:  Table [Silver].[Rooms]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Rooms]
GO
CREATE TABLE [Silver].[Rooms](
	[Tenant_ID] [int] NOT NULL,
	[Room_Id] [VARCHAR](50) NOT NULL,
	[Site_Id] [VARCHAR](50) NULL,
	[Name] [VARCHAR](255) NULL,
	[Active] [bit] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
