/****** Object:  Table [Audit].[Process_Execution_Log]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Process_Execution_Log]
GO
CREATE TABLE [Audit].[Process_Execution_Log](
	[Run_UUID] [uniqueidentifier] NULL,
	[Process_Name] [varchar](255) NULL,
	[Process_Type] [varchar](255) NULL,
	[Start_Time] [datetime2](6) NULL,
	[End_Time] [datetime2](6) NULL,
	[Duration_Seconds] [float] NULL,
	[Num_Of_Records] [int] NULL,
	[Status] [varchar](50) NULL,
	[Error_Message] [varchar](8000) NULL,
	[Workspace_Name] [varchar](255) NULL,
	[Lakehouse_Name] [varchar](255) NULL,
	[Warehouse_Name] [varchar](255) NULL,
	[Server_Name] [varchar](255) NULL,
	[Database_Name] [varchar](255) NULL,
	[Process_Result] [varchar](8000) NULL,
	[Executed_By] [varchar](255) NULL,
	[Run_Date] [date] NULL,
	[Process_Options] [varchar](255) NULL,
	[Rows_Inserted] [int] NULL,
	[Rows_Updated] [int] NULL,
	[Rows_Deleted] [int] NULL,
	[Parent_Run_UUID] [uniqueidentifier] NULL
)
GO
