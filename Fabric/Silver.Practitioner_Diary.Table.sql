/****** Object:  Table [Silver].[Practitioner_Diary]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Practitioner_Diary]
GO
CREATE TABLE [Silver].[Practitioner_Diary](
	[Tenant_ID] [int] NOT NULL,
	[Id] [VARCHAR](50) NOT NULL,
	[Practitioner_Id] [int] NULL,
	[Site_Id] [VARCHAR](50) NULL,
	[Room_Id] [VARCHAR](50) NULL,
	[Start_Time] [VARCHAR](50) NULL,
	[Finish_Time] [VARCHAR](50) NULL,
	[Day] [date] NULL,
	[Available] [bit] NULL,
	[Created_At] [VARCHAR](50) NULL,
	[Updated_At] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
