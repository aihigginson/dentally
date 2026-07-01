/****** Object:  Table [Silver].[Xero_Accounts]  ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Xero_Accounts]
GO
CREATE TABLE [Silver].[Xero_Accounts](
	[Tenant_ID] [int] NULL,
	[Xero_Tenant_ID] [varchar](100) NULL,
	[Account_ID] [varchar](100) NULL,
	[Code] [varchar](50) NULL,
	[Name] [varchar](255) NULL,
	[Account_Type] [varchar](50) NULL,
	[Account_Class] [varchar](50) NULL,
	[PL_Group] [varchar](30) NULL,          -- Income|Cost of Sales|Operating Expenses|Depreciation|Finance Costs
	[Is_PL] [bit] NULL,
	[EBITDA_Item] [bit] NULL,               -- 1 = in EBITDA (excludes depreciation/amortisation/interest/tax)
	[Reporting_Code] [varchar](50) NULL,
	[Reporting_Code_Name] [varchar](255) NULL,
	[Status] [varchar](50) NULL,
	[DW_Loaded_At] [datetime2](3) NULL,
	[DW_Updated_At] [datetime2](3) NULL
)
GO
