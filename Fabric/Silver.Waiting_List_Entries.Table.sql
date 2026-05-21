/****** Object:  Table [Silver].[Waiting_List_Entries]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Waiting_List_Entries]
GO
CREATE TABLE [Silver].[Waiting_List_Entries](
	[Tenant_ID] [int] NOT NULL,
	[Waiting_List_Entry_ID] [VARCHAR](50) NOT NULL,
	[Patient_ID] [int] NULL,
	[Practitioner_ID] [int] NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[Appointment_ID] [int] NULL,
	[Reason] [VARCHAR](255) NULL,
	[Duration] [int] NULL,
	[Status] [VARCHAR](50) NULL,
	[Notes] [VARCHAR](max) NULL,
	[Earliest_Date] [date] NULL,
	[Latest_Date] [date] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
