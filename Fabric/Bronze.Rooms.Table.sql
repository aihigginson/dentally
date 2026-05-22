/****** Object:  Table [Bronze].[Rooms]    Script Date: 19/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Rooms]
GO
CREATE TABLE [Bronze].[Rooms](
	[ID] [VARCHAR](255) NULL,
	[Name] [VARCHAR](255) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Colour] [VARCHAR](255) NULL,
	[Calendar_Position] [decimal](18, 4) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Practice_ID] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
