/****** Object:  Table [Gold].[Fact_Finance]  ******/
-- P&L fact, one row per Xero P&L transaction line. PL_Amount is the signed
-- contribution (revenue +, expense +; margin = SUM by PL_Group). Joins to the
-- existing model on Tenant_ID / fk_Date / fk_Practice_Site so Xero costs sit
-- alongside Dentally revenue.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Finance]
GO
CREATE TABLE [Gold].[Fact_Finance](
	[Tenant_ID] [int] NULL,
	[fk_GL_Account] [bigint] NULL,
	[fk_Date] [bigint] NULL,
	[fk_Practice_Site] [bigint] NULL,
	[Source] [varchar](30) NULL,
	[Doc_Type] [varchar](30) NULL,
	[Doc_Number] [varchar](100) NULL,
	[PL_Group] [varchar](30) NULL,
	[Account_Class] [varchar](50) NULL,
	[Net_Amount] [decimal](18, 4) NULL,
	[PL_Amount] [decimal](18, 4) NULL,
	[DW_Created_At] [datetime2](3) NULL
)
GO
