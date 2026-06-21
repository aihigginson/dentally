/****** Object:  Table [Silver].[Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Appointments]
GO
CREATE TABLE [Silver].[Appointments](
	[Tenant_ID] [int] NOT NULL,
	[Appointment_ID] [int] NOT NULL,
	[Appointment_UUID] [VARCHAR](50) NULL,
	[Appointment_Cancellation_Reason_ID] [VARCHAR](50) NULL,
	[Patient_ID] [int] NULL,
	[Patient_Name] [VARCHAR](255) NULL,
	[Patient_Image_Url] [VARCHAR](500) NULL,
	[Practitioner_ID] [int] NULL,
	[User_ID] [int] NULL,
	[Payment_Plan_ID] [int] NULL,
	[Room_ID] [VARCHAR](50) NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[Start_Time] [VARCHAR](50) NULL,
	[Finish_Time] [VARCHAR](50) NULL,
	[Duration] [int] NULL,
	[Reason] [VARCHAR](100) NULL,
	[State] [VARCHAR](50) NULL,
	[Booked_Via_API] [bit] NULL,
	[Pending_At] [VARCHAR](50) NULL,
	[Confirmed_At] [VARCHAR](50) NULL,
	[Arrived_At] [VARCHAR](50) NULL,
	[In_Surgery_At] [VARCHAR](50) NULL,
	[Completed_At] [VARCHAR](50) NULL,
	[Cancelled_At] [VARCHAR](50) NULL,
	[Did_Not_Attend_At] [VARCHAR](50) NULL,
	[Metadata_1_Key] [VARCHAR](40) NULL,
	[Metadata_1_Value] [VARCHAR](500) NULL,
	[Metadata_2_Key] [VARCHAR](40) NULL,
	[Metadata_2_Value] [VARCHAR](500) NULL,
	[Metadata_3_Key] [VARCHAR](40) NULL,
	[Metadata_3_Value] [VARCHAR](500) NULL,
	[Created_At] [VARCHAR](50) NULL,
	[Updated_At] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
