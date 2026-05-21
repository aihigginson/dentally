/****** Object:  Table [Silver].[Payments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Payments]
GO
CREATE TABLE [Silver].[Payments](
	[Tenant_ID] [int] NOT NULL,
	[Payment_ID] [int] NOT NULL,
	[Account_ID] [int] NULL,
	[Patient_ID] [int] NULL,
	[Practitioner_ID] [int] NULL,
	[Payment_Plan_ID] [int] NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[User_ID] [int] NULL,
	[Reference] [VARCHAR](50) NULL,
	[Transaction_Number] [VARCHAR](50) NULL,
	[Amount] [decimal](18, 4) NULL,
	[Amount_Unexplained] [decimal](18, 4) NULL,
	[Method] [VARCHAR](100) NULL,
	[Fully_Explained] [bit] NULL,
	[Deleted] [bit] NULL,
	[Status] [VARCHAR](50) NULL,
	[Dated_On] [date] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
