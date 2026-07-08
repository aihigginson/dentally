/****** Object:  Table [Bronze].[Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Appointments]
GO
CREATE TABLE [Bronze].[Appointments](
	[ID] [int] NULL,
	[Appointment_Cancellation_Reason_ID] [int] NULL,
	[Arrived_At] [VARCHAR](255) NULL,
	[Booked_Via_API] [VARCHAR](255) NULL,
	[Cancelled_At] [VARCHAR](255) NULL,
	[Completed_At] [VARCHAR](255) NULL,
	[Confirmed_At] [VARCHAR](255) NULL,
	[Did_Not_Attend_At] [VARCHAR](255) NULL,
	[Duration] [int] NULL,
	[Finish_Time] [VARCHAR](255) NULL,
	[In_Surgery_At] [VARCHAR](255) NULL,
	[Patient_Name] [VARCHAR](255) NULL,
	[Patient_ID] [int] NULL,
	[Room_ID] [VARCHAR](255) NULL,
	[Practitioner_Site_ID] [VARCHAR](50) NULL,
	[Patient_Image_Url] [VARCHAR](255) NULL,
	[Payment_Plan_ID] [int] NULL,
	[Pending_At] [VARCHAR](255) NULL,
	[Practitioner_ID] [int] NULL,
	[Reason] [VARCHAR](255) NULL,
	[Start_Time] [VARCHAR](255) NULL,
	[State] [VARCHAR](255) NULL,
	[User_ID] [int] NULL,
	[UUID] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
