/****** Object:  Table [Bronze].[Payment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Payment_Plans]
GO
CREATE TABLE [Bronze].[Payment_Plans](
	[Payment_Plan_ID] [int] NULL,
	[Payment_Plan_Active] [decimal](18, 4) NULL,
	[Payment_Plan_Created_At] [VARCHAR](255) NULL,
	[Payment_Plan_Colour] [VARCHAR](255) NULL,
	[Dentist_Recall_Interval] [decimal](18, 4) NULL,
	[Emergency_Duration] [decimal](18, 4) NULL,
	[Exam_Duration] [decimal](18, 4) NULL,
	[Exam_Scale_And_Polish_Duration] [decimal](18, 4) NULL,
	[Hygienist_Recall_Interval] [decimal](18, 4) NULL,
	[Payment_Plan_Name] [VARCHAR](255) NULL,
	[Payment_Plan_Patient_Friendly_Name] [VARCHAR](255) NULL,
	[Scale_And_Polish_Duration] [decimal](18, 4) NULL,
	[Payment_Plan_Site_ID] [VARCHAR](255) NULL
)
GO
