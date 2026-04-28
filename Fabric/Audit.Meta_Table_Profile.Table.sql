/****** Object:  Table [Audit].[Meta_Table_Profile]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Meta_Table_Profile]
GO
CREATE TABLE [Audit].[Meta_Table_Profile](
	[Meta_Table_UUID] [uniqueidentifier] NULL,
	[Medallion_Layer] [varchar](255) NULL,
	[Database_Name] [varchar](255) NULL,
	[Schema_Name] [varchar](255) NULL,
	[Table_Name] [varchar](255) NULL,
	[Table_Logical_Name] [varchar](255) NULL,
	[Table_Category] [varchar](255) NULL,
	[Table_Description] [varchar](8000) NULL,
	[Refresh_Date] [datetime2](6) NULL,
	[Record_Count] [bigint] NULL,
	[Previous_Count] [bigint] NULL
)
GO
