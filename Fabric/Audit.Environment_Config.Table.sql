/****** Object:  Table [Audit].[Environment_Config]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Environment_Config]
GO
CREATE TABLE [Audit].[Environment_Config](
	[Env_Config_Key] [varchar](255) NULL,
	[Env_Config_Value] [varchar](1000) NULL
)
GO
