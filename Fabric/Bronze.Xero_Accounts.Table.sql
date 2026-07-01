/****** Object:  Table [Bronze].[Xero_Accounts]  ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Xero_Accounts]
GO
CREATE TABLE [Bronze].[Xero_Accounts](
	[Tenant_ID] [int] NULL,
	[Xero_Tenant_ID] [varchar](100) NULL,
	[Account_ID] [varchar](100) NULL,
	[Code] [varchar](50) NULL,
	[Name] [varchar](255) NULL,
	[Account_Type] [varchar](50) NULL,
	[Account_Class] [varchar](50) NULL,
	[Reporting_Code] [varchar](50) NULL,
	[Reporting_Code_Name] [varchar](255) NULL,
	[Status] [varchar](50) NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
