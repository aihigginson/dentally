/****** Object:  Table [Gold].[Dim_Treatment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Treatment_Plans]
GO
CREATE TABLE [Gold].[Dim_Treatment_Plans](
	[pk_Treatment_Plan] [bigint] IDENTITY NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[Treatment_Plan_ID] [int] NOT NULL,
	[Nickname] [VARCHAR](255) NULL,
	[Patient_ID] [int] NULL,
	[Practitioner_ID] [int] NULL,
	[Completed] [bit] NULL,
	[Start_Date] [date] NULL,
	[End_Date] [date] NULL,
	[Completed_Date] [datetime2](3) NULL,
	[Last_Completed_Date] [date] NULL,
	[NHS_UDA_Value] [decimal](18, 4) NULL,
	[NHS_Completed_UDA_Value] [decimal](18, 4) NULL,
	[Private_Treatment_Value] [decimal](18, 4) NULL,
	[Created_Date] [datetime2](3) NULL,
	[Updated_Date] [datetime2](3) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO
