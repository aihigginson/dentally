/****** Object:  Table [Silver].[Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Recalls]
GO
CREATE TABLE [Silver].[Recalls](
	[Id] [VARCHAR](50) NOT NULL,
	[Patient_Id] [int] NULL,
	[Practitioner_Id] [int] NULL,
	[Appointment_ID] [VARCHAR](50) NULL,
	[Recall_Method] [VARCHAR](50) NULL,
	[Workflow_Status] [VARCHAR](50) NULL,
	[Workflow_Stage_ID] [VARCHAR](50) NULL,
	[First_Reminder_Type] [VARCHAR](50) NULL,
	[Second_Reminder_Type] [VARCHAR](50) NULL,
	[First_Reminder_Sent_At] [VARCHAR](50) NULL,
	[Second_Reminder_Sent_At] [VARCHAR](50) NULL,
	[Latest_Reminder_Type] [VARCHAR](50) NULL,
	[Last_Reminded_At] [VARCHAR](50) NULL,
	[Times_Contacted] [VARCHAR](50) NULL,
	[Run_Date] [VARCHAR](50) NULL,
	[Site_Id] [VARCHAR](50) NULL,
	[Recall_Type] [VARCHAR](50) NULL,
	[Due_Date] [date] NULL,
	[Interval_Months] [int] NULL,
	[Status] [VARCHAR](50) NULL,
	[Sent_At] [datetime2](3) NULL,
	[Booked_At] [datetime2](3) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
