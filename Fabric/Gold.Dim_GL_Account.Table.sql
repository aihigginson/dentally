/****** Object:  Table [Gold].[Dim_GL_Account]  ******/
-- Xero chart of accounts (general-ledger account dimension). pk assigned in the
-- load SP (no IDENTITY); -1 = unknown seed row.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_GL_Account]
GO
CREATE TABLE [Gold].[Dim_GL_Account](
	[pk_GL_Account] [bigint] NOT NULL,
	[Tenant_ID] [int] NULL,
	[bk_Account_ID] [varchar](100) NULL,
	[Account_Code] [varchar](50) NULL,
	[Account_Name] [varchar](255) NULL,
	[Account_Type] [varchar](50) NULL,
	[Account_Class] [varchar](50) NULL,
	[PL_Group] [varchar](30) NULL,
	[Is_PL] [bit] NULL,
	[EBITDA_Item] [bit] NULL,
	[Reporting_Code] [varchar](50) NULL,
	[Reporting_Code_Name] [varchar](255) NULL,
	[Status] [varchar](50) NULL,
	[DW_Created_At] [datetime2](3) NULL,
	[DW_Updated_At] [datetime2](3) NULL
)
GO
