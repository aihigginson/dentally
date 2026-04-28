/****** Object:  Table [Silver].[Acquisition_Sources]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Acquisition_Sources]
GO
CREATE TABLE [Silver].[Acquisition_Sources](
	[Acquisition_Source_Id] [VARCHAR](50) NOT NULL,
	[Active] [bit] NULL,
	[Name] [VARCHAR](255) NULL,
	[Notes] [VARCHAR](1000) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
