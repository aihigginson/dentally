/****** Object:  Table [Silver].[Appointment_Reason_Map]    Script Date: 13/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Appointment_Reason_Map]
GO
CREATE TABLE [Silver].[Appointment_Reason_Map](
	[Reason_Text]  [varchar](100)  NOT NULL,
	[Category]     [varchar](50)   NOT NULL,
	[Sort_Key]     [int]           NOT NULL
)
GO
