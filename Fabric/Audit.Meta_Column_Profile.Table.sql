/****** Object:  Table [Audit].[Meta_Column_Profile]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Meta_Column_Profile]
GO
CREATE TABLE [Audit].[Meta_Column_Profile](
	[Meta_Column_UUID] [uniqueidentifier] NULL,
	[Meta_Table_UUID] [uniqueidentifier] NULL,
	[Medallion_Layer] [varchar](255) NULL,
	[Database_Name] [varchar](255) NULL,
	[Schema_Name] [varchar](255) NULL,
	[Table_Name] [varchar](255) NULL,
	[Column_Id] [int] NULL,
	[Column_Name] [varchar](255) NULL,
	[Data_Type] [varchar](255) NULL,
	[Num_Values] [int] NULL,
	[Num_Distinct] [int] NULL,
	[Min_Value] [varchar](8000) NULL,
	[Max_Value] [varchar](8000) NULL,
	[Avg_Length] [int] NULL,
	[Refresh_Date] [datetime2](6) NULL
)
GO
