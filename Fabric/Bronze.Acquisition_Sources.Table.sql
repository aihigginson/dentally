/****** Object:  Table [Bronze].[Acquisition_Sources]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Acquisition_Sources]
GO
CREATE TABLE [Bronze].[Acquisition_Sources](
	[ID] [VARCHAR](255) NULL,
	[Active] [int] NULL,
	[Name] [VARCHAR](255) NULL,
	[Notes] [VARCHAR](max) NULL
)
GO
