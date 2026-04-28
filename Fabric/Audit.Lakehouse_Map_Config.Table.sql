/****** Object:  Table [Audit].[Lakehouse_Map_Config]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Lakehouse_Map_Config]
GO
CREATE TABLE [Audit].[Lakehouse_Map_Config](
	[Source_Workspace_Id] [varchar](36) NULL,
	[Source_Workspace_Name] [varchar](1000) NULL,
	[Source_Lakehouse_Id] [varchar](36) NULL,
	[Source_Lakehouse_Name] [varchar](1000) NULL,
	[Source_Table_Name] [varchar](1000) NULL,
	[Target_Workspace_Id] [varchar](36) NULL,
	[Target_Workspace_Name] [varchar](1000) NULL,
	[Target_Lakehouse_Id] [varchar](36) NULL,
	[Target_Lakehouse_Name] [varchar](1000) NULL,
	[Target_Table_Name] [varchar](1000) NULL
)
GO
