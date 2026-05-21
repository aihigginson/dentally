/****** Object:  Table [Silver].[Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Recalls]
GO
CREATE TABLE [Silver].[Recalls](
	[Tenant_ID]               [int]           NOT NULL,
	[Id]                      [VARCHAR](50)   NOT NULL,
	[Patient_ID]              [int]           NULL,
	[Appointment_ID]          [VARCHAR](50)   NULL,
	[Recall_Type]             [VARCHAR](50)   NULL,
	[Recall_Method]           [VARCHAR](50)   NULL,
	[Status]                  [VARCHAR](50)   NULL,
	[Prebooked]               [VARCHAR](10)   NULL,
	[Due_Date]                [date]          NULL,
	[First_Reminder_Sent_At]  [VARCHAR](50)   NULL,
	[First_Reminder_Type]     [VARCHAR](50)   NULL,
	[Second_Reminder_Sent_At] [VARCHAR](50)   NULL,
	[Second_Reminder_Type]    [VARCHAR](50)   NULL,
	[Last_Reminded_At]        [VARCHAR](50)   NULL,
	[Latest_Reminder_Type]    [VARCHAR](50)   NULL,
	[Times_Contacted]         [VARCHAR](50)   NULL,
	[Run_Date]                [VARCHAR](50)   NULL,
	[Workflow_Status]         [VARCHAR](50)   NULL,
	[Workflow_Stage_ID]       [VARCHAR](50)   NULL,
	[First_Reminder_ID]       [VARCHAR](50)   NULL,
	[Second_Reminder_ID]      [VARCHAR](50)   NULL,
	[DW_Created_At]           [datetime2](6)  NOT NULL,
	[DW_Updated_At]           [datetime2](6)  NOT NULL,
	[_Row_Hash]               [varbinary](32) NULL,
	[_Raw_Json]               [VARCHAR](max)  NULL
)
GO
