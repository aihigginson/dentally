/****** Object:  Table [Bronze].[Treatment_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Treatment_Appointments]
GO
CREATE TABLE [Bronze].[Treatment_Appointments](
	[ID] [varchar](255) NULL,
	[Bookable] [int] NULL,
	[Notes] [varchar](4000) NULL,
	[Position] [int] NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Appointment_ID] [int] NULL,
	[Patient_ID] [int] NULL,
	[Treatment_Plan_ID] [int] NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
