/****** Object:  Table [Bronze].[Sundries]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Sundries]
GO
CREATE TABLE [Bronze].[Sundries](
	[ID] [VARCHAR](255) NULL,
	[Name] [VARCHAR](255) NULL,
	[Nickname] [VARCHAR](255) NULL,
	[Price] [decimal](18, 4) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
