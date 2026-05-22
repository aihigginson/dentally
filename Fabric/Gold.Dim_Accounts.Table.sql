/****** Object:  Table [Gold].[Dim_Accounts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Accounts]
GO
CREATE TABLE [Gold].[Dim_Accounts](
	[pk_Account] [bigint] NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[Account_ID] [int] NOT NULL,
	[Patient_ID] [int] NULL,
	[Patient_Name] [VARCHAR](255) NULL,
	[Current_Balance] [decimal](18, 4) NULL,
	[Opening_Balance] [decimal](18, 4) NULL,
	[Planned_NHS_Treatment_Value] [decimal](18, 4) NULL,
	[Planned_Private_Treatment_Value] [decimal](18, 4) NULL,
	[Account_Count] [int] NOT NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO
