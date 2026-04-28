/****** Object:  Table [Bronze].[NHS_Codes]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[NHS_Codes]
GO
CREATE TABLE [Bronze].[NHS_Codes](
	[Code] [decimal](18, 4) NULL,
	[Area] [VARCHAR](255) NULL,
	[Codedescription] [VARCHAR](255) NULL
)
GO
