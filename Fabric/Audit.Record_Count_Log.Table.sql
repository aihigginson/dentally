/****** Object:  Table [Audit].[Record_Count_Log]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Record_Count_Log]
GO
CREATE TABLE [Audit].[Record_Count_Log](
	[Record_Count_UUID] [uniqueidentifier] NULL,
	[Log_Date] [datetime2](6) NULL,
	[Medallion_Layer] [varchar](255) NULL,
	[Database_Name] [varchar](255) NULL,
	[Schema_Name] [varchar](255) NULL,
	[Table_Name] [varchar](255) NULL,
	[Record_Count] [int] NULL
)
GO
