/****** Object:  Table [Gold].[Fact_Payments]    Script Date: 22/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Payments]
GO
CREATE TABLE [Gold].[Fact_Payments](
	[pk_Payment]          [bigint]         NOT NULL IDENTITY,
	[Tenant_ID]           [int]            NOT NULL,
	[bk_Payment_ID]       [int]            NOT NULL,
	[fk_Patient]          [bigint]         NULL,
	[fk_Practitioner]     [bigint]         NULL,
	[fk_Practice_Site]    [bigint]         NULL,
	[fk_Date_Payment]     [bigint]         NULL,
	[Payment_Method]      [varchar](100)   NULL,
	[Payment_Amount]      [decimal](12,2)  NULL,
	[Is_Deposit]          [bit]            NULL,
	[Deposit_Amount]      [decimal](12,2)  NULL,
	[DW_Created_At]       [datetime2](6)   NOT NULL,
	[DW_Updated_At]       [datetime2](6)   NOT NULL
)
GO
