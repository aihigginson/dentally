/****** Object:  Table [Silver].[Practitioner_Diary_Breaks]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Practitioner_Diary_Breaks]
GO
CREATE TABLE [Silver].[Practitioner_Diary_Breaks](
	[Practitioner_Diary_ID] [VARCHAR](255) NULL,
	[Break_Name] [varchar](255) NULL,
	[Start_Time] [VARCHAR](255) NULL,
	[End_Time] [VARCHAR](255) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
