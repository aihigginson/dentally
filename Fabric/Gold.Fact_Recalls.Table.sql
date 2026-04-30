/****** Object:  Table [Gold].[Fact_Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Recalls]
GO
CREATE TABLE [Gold].[Fact_Recalls](
	[pk_Recall] [bigint] IDENTITY NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[bk_Recall_ID] [VARCHAR](50) NOT NULL,
	[fk_Patient] [bigint] NULL,
	[fk_Date_Due] [bigint] NULL,
	[fk_Date_Run] [bigint] NULL,
	[fk_Date_First_Reminder] [bigint] NULL,
	[fk_Date_Second_Reminder] [bigint] NULL,
	[fk_Date_Last_Reminded] [bigint] NULL,
	[Appointment_ID] [VARCHAR](50) NULL,
	[Recall_Type] [VARCHAR](100) NULL,
	[Recall_Method] [VARCHAR](100) NULL,
	[Status] [VARCHAR](100) NULL,
	[Workflow_Status] [VARCHAR](100) NULL,
	[Workflow_Stage_ID] [VARCHAR](50) NULL,
	[First_Reminder_Type] [VARCHAR](100) NULL,
	[Second_Reminder_Type] [VARCHAR](100) NULL,
	[Latest_Reminder_Type] [VARCHAR](100) NULL,
	[Times_Contacted] [int] NULL,
	[Due_Date] [date] NULL,
	[Run_Date] [date] NULL,
	[Days_Overdue] [int] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO


