/****** Object:  Table [Silver].[Treatment_Plan_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Treatment_Plan_Items]
GO
CREATE TABLE [Silver].[Treatment_Plan_Items](
	[Tenant_ID] [int] NOT NULL,
	[Id] [VARCHAR](50) NOT NULL,
	[Treatment_Plan_Id] [int] NULL,
	[Payment_Plan_Id] [int] NULL,
	[Treatment_Id] [int] NULL,
	[Patient_Id] [int] NULL,
	[Practitioner_Id] [int] NULL,
	[Fee_Id] [uniqueidentifier] NULL,
	[Name] [VARCHAR](255) NULL,
	[Description] [VARCHAR](max) NULL,
	[Quantity] [int] NULL,
	[Price] [decimal](18, 4) NULL,
	[Total_Price] [decimal](18, 4) NULL,
	[Nhs_Charge] [bit] NULL,
	[Status] [VARCHAR](50) NULL,
	[Tooth] [VARCHAR](50) NULL,
	[Surface] [VARCHAR](50) NULL,
	[Region] [VARCHAR](50) NULL,
	[Invoice_ID] [VARCHAR](255) NULL,
	[Treatment_Appointment_ID] [VARCHAR](255) NULL,
	[Referrer_ID] [VARCHAR](255) NULL,
	[Nomenclature] [VARCHAR](255) NULL,
	[Patient_Nomenclature] [VARCHAR](255) NULL,
	[NHS_Treatment_Cat] [VARCHAR](255) NULL,
	[UDA_Band] [VARCHAR](255) NULL,
	[Notes] [VARCHAR](255) NULL,
	[Position] [int] NULL,
	[Base_Chart] [int] NULL,
	[Completed] [int] NULL,
	[Charged] [int] NULL,
	[Appear_On_Invoice] [int] NULL,
	[Duration] [int] NULL,
	[Completed_At] [VARCHAR](50) NULL,
	[Created_At] [VARCHAR](50) NULL,
	[Updated_At] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
