/****** Object:  Table [Silver].[Treatments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Treatments]
GO
CREATE TABLE [Silver].[Treatments](
	[Tenant_ID] [int] NOT NULL,
	[Id] [int] NOT NULL,
	[Site_Id] [VARCHAR](50) NULL,
	[Code] [VARCHAR](50) NULL,
	[Name] [VARCHAR](255) NULL,
	[Description] [VARCHAR](255) NULL,
	[Type] [VARCHAR](50) NULL,
	[Active] [bit] NULL,
	[Nomenclature] [VARCHAR](255) NULL,
	[Patient_Nomenclature] [VARCHAR](255) NULL,
	[Patient_Description] [VARCHAR](255) NULL,
	[Notes] [VARCHAR](255) NULL,
	[Region] [VARCHAR](255) NULL,
	[UDA_Band] [decimal](10, 2) NULL,
	[NHS_Treatment_Cat] [decimal](10, 2) NULL,
	[Treatment_Category_ID] [int] NULL,
	[Created_At] [VARCHAR](20) NULL,
	[Updated_At] [VARCHAR](20) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
