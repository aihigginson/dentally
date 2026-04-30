/****** Object:  Table [Bronze].[Payments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Payments]
GO
CREATE TABLE [Bronze].[Payments](
	[Payment_ID] [decimal](18, 4) NULL,
	[Account_ID] [decimal](18, 4) NULL,
	[Amount] [decimal](18, 4) NULL,
	[Amount_Unexplained] [decimal](18, 4) NULL,
	[Dated_On] [VARCHAR](255) NULL,
	[Deleted] [decimal](18, 4) NULL,
	[Fully_Explained] [decimal](18, 4) NULL,
	[Method] [VARCHAR](255) NULL,
	[Patient_ID] [decimal](18, 4) NULL,
	[Payment_Plan_ID] [int] NULL,
	[Practitioner_ID] [int] NULL,
	[Reference] [decimal](18, 4) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Status] [VARCHAR](255) NULL,
	[Transaction_Number] [decimal](18, 4) NULL,
	[User_ID] [int] NULL,
	[Explanation_Amount] [decimal](18, 4) NULL,
	[Explanation_Comments] [VARCHAR](255) NULL,
	[Explanation_ID] [decimal](18, 4) NULL,
	[Explanation_Invoice_ID] [decimal](18, 4) NULL,
	[Explanation_Invoice_Reference] [decimal](18, 4) NULL,
	[Explanation_Payment_Reference] [decimal](18, 4) NULL,
	[Explanation_User_ID] [decimal](18, 4) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
