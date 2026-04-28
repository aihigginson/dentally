/****** Object:  Table [Audit].[Process_Message_Log]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Process_Message_Log]
GO
CREATE TABLE [Audit].[Process_Message_Log](
	[Message_UUID] [uniqueidentifier] NULL,
	[Run_UUID] [uniqueidentifier] NULL,
	[Process_Name] [varchar](255) NULL,
	[Message_Date] [datetime2](6) NULL,
	[Message_Level] [smallint] NULL,
	[Message_Text] [varchar](8000) NULL
)
GO
