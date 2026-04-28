/****** Object:  Table [Bronze].[Bank_Holidays]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Bank_Holidays]
GO
CREATE TABLE [Bronze].[Bank_Holidays](
	[ID] [int] NOT NULL,
	[Division] [VARCHAR](50) NOT NULL,
	[Holiday_Date] [date] NOT NULL,
	[Title] [VARCHAR](200) NOT NULL,
	[Notes] [VARCHAR](500) NULL,
	[Bunting] [int] NOT NULL,
	[Loaded_At] [datetime2](6) NOT NULL
)
GO
