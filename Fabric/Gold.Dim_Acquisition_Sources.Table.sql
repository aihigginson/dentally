/****** Object:  Table [Gold].[Dim_Acquisition_Sources]    Script Date: 29/05/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Acquisition_Sources]
GO
CREATE TABLE [Gold].[Dim_Acquisition_Sources](
	[pk_Acquisition_Source] [bigint] NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[Acquisition_Source_ID] [VARCHAR](50) NOT NULL,
	[Active] [bit] NULL,
	[Name] [VARCHAR](255) NULL,
	[Standard_Acquisition_Source] [VARCHAR](100) NULL,
	[Notes] [VARCHAR](1000) NULL,
	[Acquisition_Source_Count] [int] NOT NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO
