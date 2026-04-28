/****** Object:  Table [Audit].[Process_Type]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Process_Type]
GO
CREATE TABLE [Audit].[Process_Type](
	[Process_Type_Code] [varchar](100) NULL,
	[Process_Type_Desc] [varchar](1000) NULL
)
GO
