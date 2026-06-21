/****** Object:  Table [Gold].[Fact_Treatment_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Treatment_Appointments]
GO
CREATE TABLE [Gold].[Fact_Treatment_Appointments](
	[pk_Treatment_Appointment] [bigint] IDENTITY NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[bk_Treatment_Appointment_ID] [VARCHAR](50) NOT NULL,
	[fk_Patient] [bigint] NULL,
	[fk_Treatment_Plan] [bigint] NULL,
	[fk_Date_Appointment] [bigint] NULL,
	[fk_Date_Created] [bigint] NULL,
	[Appointment_ID] [int] NULL,
	[Treatment_Plan_ID] [int] NULL,
	[Position] [int] NULL,
	[Bookable] [bit] NULL,
	[Created_At] [datetime2](3) NULL,
	[Updated_At] [datetime2](3) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO


