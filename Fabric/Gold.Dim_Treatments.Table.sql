/****** Object:  Table [Gold].[Dim_Treatments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Treatments]
GO
CREATE TABLE [Gold].[Dim_Treatments](
	[pk_Treatment] [bigint] IDENTITY NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[Treatment_ID] [int] NOT NULL,
	[Treatment_Code] [VARCHAR](50) NULL,
	[Nomenclature] [VARCHAR](255) NULL,
	[Patient_Nomenclature] [VARCHAR](255) NULL,
	[Description] [VARCHAR](max) NULL,
	[Patient_Description] [VARCHAR](255) NULL,
	[Notes] [VARCHAR](255) NULL,
	[Region] [VARCHAR](100) NULL,
	[UDA_Band] [int] NULL,
	[NHS_Treatment_Cat] [int] NULL,
	[Treatment_Category_ID] [int] NULL,
	[Treatment_Category_Name] [VARCHAR](255) NULL,
	[Created_Date] [datetime2](3) NULL,
	[Updated_Date] [datetime2](3) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO
