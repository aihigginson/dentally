/****** Object:  Table [Bronze].[Treatments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Treatments]
GO
CREATE TABLE [Bronze].[Treatments](
	[ID] [int] NULL,
	[Active] [int] NULL,
	[Code] [VARCHAR](255) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Description] [VARCHAR](max) NULL,
	[NHS_Treatment_Cat] [VARCHAR](255) NULL,
	[Nomenclature] [VARCHAR](255) NULL,
	[Notes] [VARCHAR](255) NULL,
	[Patient_Description] [VARCHAR](255) NULL,
	[Patient_Nomenclature] [VARCHAR](255) NULL,
	[Region] [VARCHAR](255) NULL,
	[Treatment_Category_ID] [decimal](18, 4) NULL,
	[UDA_Band] [decimal](18, 4) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
