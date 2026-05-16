/****** Object:  Table [Bronze].[Waiting_Lists]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Waiting_Lists]
GO
CREATE TABLE [Bronze].[Waiting_Lists](
	[ID] [VARCHAR](255) NULL,
	[Active] [decimal](18, 4) NULL,
	[Default_Appointment_Duration] [decimal](18, 4) NULL,
	[Default_Appointment_Reason] [VARCHAR](255) NULL,
	[Default_Notes] [VARCHAR](255) NULL,
	[Default_Status] [VARCHAR](255) NULL,
	[Default_Treatment_Duration] [decimal](18, 4) NULL,
	[Default_Treatment_Reason] [VARCHAR](255) NULL,
	[Name] [VARCHAR](255) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Target_Appointment_Days] [decimal](18, 4) NULL,
	[Target_Treatment_Days] [decimal](18, 4) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
