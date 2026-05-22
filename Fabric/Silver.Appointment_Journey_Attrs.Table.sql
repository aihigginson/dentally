/****** Object:  Table [Silver].[Appointment_Journey_Attrs]    Script Date: 13/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Appointment_Journey_Attrs]
GO
CREATE TABLE [Silver].[Appointment_Journey_Attrs](
	[Tenant_ID]          [int]          NOT NULL,
	[Appointment_ID]     [int]          NOT NULL,
	[Booking]            [varchar](50)  NULL,
	[This_Visit]         [varchar](50)  NULL,
	[Next_Visit]         [varchar](50)  NULL,
	[Future_Appointment] [varchar](50)  NULL,
	[DW_Created_At]      [datetime2](6) NOT NULL,
	[DW_Updated_At]      [datetime2](6) NOT NULL
)
GO
