/****** Object:  Table [Silver].[Payment_Explanations]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Payment_Explanations]
GO
CREATE TABLE [Silver].[Payment_Explanations](
	[Tenant_ID] [int] NOT NULL,
	[Explanation_Id] [int] NOT NULL,
	[Payment_Id] [int] NULL,
	[Invoice_Id] [int] NULL,
	[User_Id] [int] NULL,
	[Payment_Reference] [VARCHAR](50) NULL,
	[Invoice_Reference] [VARCHAR](50) NULL,
	[Amount] [decimal](18, 4) NULL,
	[Comments] [VARCHAR](max) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
