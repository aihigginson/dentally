/****** Object:  Table [Bronze].[Treatment_Categories]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Treatment_Categories]
GO
CREATE TABLE [Bronze].[Treatment_Categories](
	[ID] [decimal](18, 4) NULL,
	[Name] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
