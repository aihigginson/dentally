/****** Object:  Table [Bronze].[Accounts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Accounts]
GO
CREATE TABLE [Bronze].[Accounts](
	[Account_ID] [int] NULL,
	[Current_Balance] [VARCHAR](255) NULL,
	[Opening_Balance] [VARCHAR](255) NULL,
	[Patient_ID] [int] NULL,
	[Patient_Name] [VARCHAR](255) NULL,
	[Planned_NHS_Treatment_Value] [VARCHAR](255) NULL,
	[Planned_Private_Treatment_Value] [VARCHAR](255) NULL
)
GO
