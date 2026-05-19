/****** Object:  Table [Bronze].[Treatment_Plan_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Treatment_Plan_Items]
GO
CREATE TABLE [Bronze].[Treatment_Plan_Items](
	[ID] [varchar](50) NULL,
	[Appear_On_Invoice] [decimal](18, 4) NULL,
	[Base_Chart] [decimal](18, 4) NULL,
	[Charged] [decimal](18, 4) NULL,
	[Completed] [decimal](18, 4) NULL,
	[Completed_At] [VARCHAR](255) NULL,
	[Duration] [decimal](18, 4) NULL,
	[NHS_Treatment_Cat] [VARCHAR](255) NULL,
	[Nomenclature] [VARCHAR](255) NULL,
	[Notes] [VARCHAR](255) NULL,
	[Patient_Nomenclature] [VARCHAR](255) NULL,
	[Position] [decimal](18, 4) NULL,
	[Price] [decimal](18, 4) NULL,
	[Region] [VARCHAR](255) NULL,
	[UDA_Band] [VARCHAR](255) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Invoice_ID] [VARCHAR](255) NULL,
	[Patient_ID] [decimal](18, 4) NULL,
	[Payment_Plan_ID] [int] NULL,
	[Practitioner_ID] [int] NULL,
	[Referrer_ID] [decimal](18, 4) NULL,
	[Treatment_Appointment_ID] [VARCHAR](255) NULL,
	[Treatment_ID] [decimal](18, 4) NULL,
	[Treatment_Plan_ID] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
