/****** Object:  Table [Bronze].[Treatment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Treatment_Plans]
GO
CREATE TABLE [Bronze].[Treatment_Plans](
	[ID] [decimal](18, 4) NULL,
	[Completed] [decimal](18, 4) NULL,
	[Completed_At] [VARCHAR](255) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[End_Date] [VARCHAR](255) NULL,
	[Last_Completed_At] [VARCHAR](255) NULL,
	[NHS_Completed_UDA_Value] [decimal](18, 4) NULL,
	[NHS_UDA_Value] [decimal](18, 4) NULL,
	[Nickname] [VARCHAR](255) NULL,
	[Patient_ID] [decimal](18, 4) NULL,
	[Practitioner_ID] [int] NULL,
	[Private_Treatment_Value] [decimal](18, 4) NULL,
	[Start_Date] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
