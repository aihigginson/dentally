/****** Object:  Table [Bronze].[Practitioner_Diary]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Practitioner_Diary]
GO
CREATE TABLE [Bronze].[Practitioner_Diary](
	[ID] [VARCHAR](255) NULL,
	[Day] [VARCHAR](255) NULL,
	[End_Time] [VARCHAR](255) NULL,
	[Start_Time] [VARCHAR](255) NULL,
	[Unavailable] [decimal](18, 4) NULL,
	[Practitioner_ID] [int] NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
