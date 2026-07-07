/****** Object:  Table [Silver].[Treatment_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Treatment_Appointments]
GO
CREATE TABLE [Silver].[Treatment_Appointments](
	[Tenant_ID] [int] NOT NULL,
	[Id] [VARCHAR](50) NOT NULL,
	[Appointment_ID] [int] NULL,
	[Treatment_Plan_Item_ID] [VARCHAR](50) NULL,
	[Treatment_Plan_ID] [int] NULL,
	[Patient_ID] [int] NULL,
	[Practitioner_ID] [int] NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[Status] [VARCHAR](50) NULL,
	[Position] [int] NULL,
	[Bookable] [int] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
