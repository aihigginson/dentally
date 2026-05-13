/****** Object:  Table [Gold].[Fact_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Appointments]
GO
CREATE TABLE [Gold].[Fact_Appointments](
	[pk_Appointment] [bigint] IDENTITY NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[bk_Appointment_ID] [int] NOT NULL,
	[fk_Patient] [bigint] NULL,
	[fk_Practitioner] [bigint] NULL,
	[fk_Payment_Plan] [bigint] NULL,
	[fk_Practice_Site] [bigint] NULL,
	[fk_User] [bigint] NULL,
	[fk_Date_Start] [bigint] NULL,
	[fk_Date_Pending] [bigint] NULL,
	[fk_Date_Created] [bigint] NULL,
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
	[In_Surgery_Mins]    [int]          NULL,
	[Booking]            [varchar](50)  NULL,
	[This_Visit]         [varchar](50)  NULL,
	[Next_Visit]         [varchar](50)  NULL,
	[Future_Appointment] [varchar](50)  NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO



