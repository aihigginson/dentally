/****** Object:  Table [Bronze].[Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Recalls]
GO
CREATE TABLE [Bronze].[Recalls](
	[ID] [VARCHAR](255) NULL,
	[Patient_ID] [decimal](18, 4) NULL,
	[Practitioner_ID] [decimal](18, 4) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Recall_Date] [VARCHAR](255) NULL,
	[Recall_Type] [VARCHAR](255) NULL,
	[Interval_Months] [decimal](18, 4) NULL,
	[Status] [VARCHAR](255) NULL,
	[Notes] [VARCHAR](max) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
