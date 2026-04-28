/****** Object:  Table [Audit].[Process_Dependency]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Process_Dependency]
GO
CREATE TABLE [Audit].[Process_Dependency](
	[Prev_Process_Code] [varchar](100) NULL,
	[Next_Process_Code] [varchar](100) NULL,
	[Dependency_Type] [varchar](1000) NULL,
	[Dependency_Level] [int] NULL,
	[Is_Active] [smallint] NULL,
	[On_Prev_Error] [varchar](100) NULL,
	[On_Next_Error] [varchar](100) NULL
)
GO
