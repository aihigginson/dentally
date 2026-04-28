/****** Object:  Table [Audit].[Process_Execution_Temp]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Process_Execution_Temp]
GO
CREATE TABLE [Audit].[Process_Execution_Temp](
	[Run_UUID] [uniqueidentifier] NULL,
	[End_Time] [datetime2](6) NULL,
	[Duration_Seconds] [float] NULL,
	[Num_Of_Records] [int] NULL,
	[Status] [varchar](50) NULL,
	[Error_Message] [varchar](8000) NULL,
	[Process_Result] [varchar](8000) NULL,
	[Rows_Inserted] [int] NULL,
	[Rows_Updated] [int] NULL,
	[Rows_Deleted] [int] NULL
)
GO
