/****** Object:  Table [Silver].[Appointment_Journey_Attributes]    Script Date: 31/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Appointment_Journey_Attributes]
GO
CREATE TABLE [Silver].[Appointment_Journey_Attributes](
	[Tenant_ID]          [int]          NOT NULL,
	[Appointment_ID]     [int]          NOT NULL,
	[Booking]            [varchar](50)  NULL,
	[Appointment_Reason] [varchar](50)  NULL,
	[DW_Created_At]      [datetime2](6) NOT NULL,
	[DW_Updated_At]      [datetime2](6) NOT NULL
)
GO
