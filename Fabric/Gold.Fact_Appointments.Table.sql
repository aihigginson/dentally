/****** Object:  Table [Gold].[Fact_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Appointments]
GO
CREATE TABLE [Gold].[Fact_Appointments](
	[pk_Appointment] [bigint] IDENTITY NOT NULL,
	[bk_Appointment_ID] [int] NOT NULL,
	[fk_Patient] [int] NULL,
	[fk_Practitioner] [int] NULL,
	[fk_Payment_Plan] [int] NULL,
	[fk_Practice_Site] [int] NULL,
	[fk_User] [int] NULL,
	[fk_Date_Start] [int] NULL,
	[fk_Date_Pending] [int] NULL,
	[fk_Date_Created] [int] NULL,
	[Room_ID] [VARCHAR](50) NULL,
	[State] [VARCHAR](50) NULL,
	[Reason] [VARCHAR](100) NULL,
	[Treatment_Description] [VARCHAR](max) NULL,
	[Notes] [VARCHAR](max) NULL,
	[Cancellation_Reason_ID] [VARCHAR](50) NULL,
	[Arrived_At] [datetime2](3) NULL,
	[In_Surgery_At] [datetime2](3) NULL,
	[Completed_At] [datetime2](3) NULL,
	[Confirmed_At] [datetime2](3) NULL,
	[Cancelled_At] [datetime2](3) NULL,
	[Did_Not_Attend_At] [datetime2](3) NULL,
	[Start_Time] [datetime2](3) NULL,
	[Finish_Time] [datetime2](3) NULL,
	[Pending_At] [datetime2](3) NULL,
	[Is_Completed] [bit] NULL,
	[Is_Cancelled] [bit] NULL,
	[Is_DNA] [bit] NULL,
	[Is_Arrived] [bit] NULL,
	[Duration_Mins] [int] NULL,
	[Waiting_Mins] [int] NULL,
	[In_Surgery_Mins] [int] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO



