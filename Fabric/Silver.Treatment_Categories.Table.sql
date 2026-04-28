/****** Object:  Table [Silver].[Treatment_Categories]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Treatment_Categories]
GO
CREATE TABLE [Silver].[Treatment_Categories](
	[Id] [VARCHAR](50) NOT NULL,
	[Name] [VARCHAR](255) NULL,
	[Description] [VARCHAR](255) NULL,
	[Colour] [VARCHAR](20) NULL,
	[Position] [int] NULL,
	[Active] [bit] NULL,
	[Created_At] [VARCHAR](20) NULL,
	[Updated_At] [VARCHAR](20) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
