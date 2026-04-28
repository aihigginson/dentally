/****** Object:  Table [Audit].[Process_Config]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Process_Config]
GO
CREATE TABLE [Audit].[Process_Config](
	[Process_Code] [varchar](100) NULL,
	[Process_Name] [varchar](1000) NULL,
	[Process_Desc] [varchar](8000) NULL,
	[Process_Parameters] [varchar](4000) NULL,
	[Process_Category_Code] [varchar](100) NULL,
	[Process_Type_Code] [varchar](100) NULL
)
GO
