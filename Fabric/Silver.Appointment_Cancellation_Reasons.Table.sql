/****** Object:  Table [Silver].[Appointment_Cancellation_Reasons]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Appointment_Cancellation_Reasons]
GO
CREATE TABLE [Silver].[Appointment_Cancellation_Reasons](
	[Tenant_ID] [int] NOT NULL,
	[Cancellation_Reason_Id] [VARCHAR](50) NOT NULL,
	[Archived] [bit] NULL,
	[Reason] [VARCHAR](255) NULL,
	[Reason_Type] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
