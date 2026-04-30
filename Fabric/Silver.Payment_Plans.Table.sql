/****** Object:  Table [Silver].[Payment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Payment_Plans]
GO
CREATE TABLE [Silver].[Payment_Plans](
	[Tenant_ID] [int] NOT NULL,
	[Payment_Plan_Id] [int] NOT NULL,
	[Payment_Plan_Site_Id] [VARCHAR](50) NULL,
	[Payment_Plan_Active] [bit] NULL,
	[Payment_Plan_Colour] [VARCHAR](20) NULL,
	[Dentist_Recall_Interval] [int] NULL,
	[Emergency_Duration] [int] NULL,
	[Exam_Duration] [int] NULL,
	[Exam_Scale_And_Polish_Duration] [int] NULL,
	[Hygienist_Recall_Interval] [int] NULL,
	[Payment_Plan_Name] [VARCHAR](255) NULL,
	[Payment_Plan_Patient_Friendly_Name] [VARCHAR](255) NULL,
	[Scale_And_Polish_Duration] [int] NULL,
	[Payment_Plan_Created_At] [datetime2](3) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
