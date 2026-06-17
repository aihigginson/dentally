/****** Object:  Table [Gold].[Fact_Treatment_Plan_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Treatment_Plan_Items]
GO
CREATE TABLE [Gold].[Fact_Treatment_Plan_Items](
	[pk_Treatment_Plan_Item] [bigint] IDENTITY NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[bk_Treatment_Plan_Item_ID] [VARCHAR](50) NOT NULL,
	[fk_Treatment_Plan] [bigint] NULL,
	[fk_Patient] [bigint] NULL,
	[fk_Practitioner] [bigint] NULL,
	[fk_Payment_Plan] [bigint] NULL,
	[fk_Treatment] [bigint] NULL,
	[fk_Date_Created] [bigint] NULL,
	[fk_Date_Completed] [bigint] NULL,
	[fk_Date_Updated] [bigint] NULL,
	[Treatment_Plan_ID] [int] NULL,
	[Invoice_ID] [int] NULL,
	[Treatment_Appointment_ID] [VARCHAR](50) NULL,
	[Referrer_ID] [int] NULL,
	[Nomenclature] [VARCHAR](255) NULL,
	[NHS_Treatment_Cat] [VARCHAR](50) NULL,
	[UDA_Band] [VARCHAR](50) NULL,
	[Region] [VARCHAR](100) NULL,
	[Position] [int] NULL,
	[Base_Chart] [bit] NULL,
	[Completed] [bit] NULL,
	[Charged] [bit] NULL,
	[Appear_On_Invoice] [bit] NULL,
	[Price] [decimal](18, 4) NULL,
	[Duration_Mins] [int] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO




