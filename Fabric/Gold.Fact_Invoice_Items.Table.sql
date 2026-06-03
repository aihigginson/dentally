/****** Object:  Table [Gold].[Fact_Invoice_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Invoice_Items]
GO
CREATE TABLE [Gold].[Fact_Invoice_Items](
	[pk_Invoice_Item] [bigint] IDENTITY NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[bk_Invoice_Item_ID] [VARCHAR](255) NOT NULL,
	[fk_Patient] [bigint] NULL,
	[fk_Practitioner] [bigint] NULL,
	[fk_Payment_Plan] [bigint] NULL,
	[fk_Treatment_Plan] [bigint] NULL,
	[fk_Account] [bigint] NULL,
	[fk_Practice_Site] [bigint] NULL,
	[fk_User] [bigint] NULL,
	[fk_Date_Invoice] [bigint] NULL,
	[fk_Date_Due] [bigint] NULL,
	[fk_Date_Paid] [bigint] NULL,
	[fk_Date_Created] [bigint] NULL,
	[Invoice_ID] [bigint] NULL,
	[Treatment_Plan_Item_ID] [bigint] NULL,
	[Sundry_ID] [VARCHAR](255) NULL,
	[Item_Name] [VARCHAR](255) NULL,
	[Invoice_Reference] [int] NULL,
	[Invoice_Payment_Terms] [VARCHAR](255) NULL,
	[Invoice_Footnote] [VARCHAR](255) NULL,
	[Invoice_Paid] [bit] NULL,
	[Item_Price] [decimal](12, 2) NULL,
	[Quantity] [decimal](10, 4) NULL,
	[Total_Price] [decimal](12, 2) NULL,
	[NHS_Charge] [decimal](12, 2) NULL,
	[Invoice_Amount] [decimal](12, 2) NULL,
	[Invoice_Amount_Outstanding] [decimal](12, 2) NULL,
	[Invoice_NHS_Amount] [decimal](12, 2) NULL,
	[Aged_Debt_Band] [VARCHAR](20) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO




