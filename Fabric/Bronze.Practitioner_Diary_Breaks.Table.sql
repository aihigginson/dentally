/****** Object:  Table [Bronze].[Practitioner_Diary_Breaks]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Practitioner_Diary_Breaks]
GO
CREATE TABLE [Bronze].[Practitioner_Diary_Breaks](
	[ID] [VARCHAR](255) NULL,
	[Practitioner_Diary_ID] [VARCHAR](255) NULL,
	[Name] [varchar](255) NULL,
	[Start_Time] [VARCHAR](255) NULL,
	[End_Time] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
