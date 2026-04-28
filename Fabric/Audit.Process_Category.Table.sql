/****** Object:  Table [Audit].[Process_Category]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Process_Category]
GO
CREATE TABLE [Audit].[Process_Category](
	[Process_Category_Code] [varchar](100) NULL,
	[Process_Category_Desc] [varchar](1000) NULL
)
GO
