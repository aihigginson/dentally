/****** Object:  Table [Gold].[Dim_Payment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Payment_Plans]
GO
CREATE TABLE [Gold].[Dim_Payment_Plans](
	[pk_Payment_Plan] [bigint] NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[Payment_Plan_ID] [int] NOT NULL,
	[Payment_Plan_Name] [VARCHAR](255) NULL,
	[Patient_Friendly_Name] [VARCHAR](255) NULL,
	[Active] [bit] NULL,
	[Colour] [VARCHAR](20) NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[Dentist_Recall_Interval_Months] [int] NULL,
	[Hygienist_Recall_Interval_Months] [int] NULL,
	[Emergency_Duration_Mins] [int] NULL,
	[Exam_Duration_Mins] [int] NULL,
	[Exam_Scale_Polish_Duration_Mins] [int] NULL,
	[Scale_Polish_Duration_Mins] [int] NULL,
	[Created_Date] [datetime2](3) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO
