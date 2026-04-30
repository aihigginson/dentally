/****** Object:  Table [Silver].[Sundries]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Sundries]
GO
CREATE TABLE [Silver].[Sundries](
	[Tenant_ID] [int] NOT NULL,
	[Sundry_Id] [int] NOT NULL,
	[Site_Id] [VARCHAR](50) NULL,
	[Name] [VARCHAR](255) NULL,
	[Price] [decimal](18, 4) NULL,
	[Active] [bit] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
