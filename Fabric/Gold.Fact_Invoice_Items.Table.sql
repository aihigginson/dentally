/****** Object:  Table [Gold].[Fact_Invoice_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Invoice_Items]
GO
CREATE TABLE [Gold].[Fact_Invoice_Items](
	[pk_Invoice_Item] [bigint] IDENTITY NOT NULL,
	[bk_Invoice_Item_ID] [VARCHAR](255) NOT NULL,
	[fk_Patient] [int] NULL,
	[fk_Practitioner] [int] NULL,
	[fk_Payment_Plan] [int] NULL,
	[fk_Treatment_Plan] [int] NULL,
	[fk_Account] [int] NULL,
	[fk_Practice_Site] [int] NULL,
	[fk_User] [int] NULL,
	[fk_Date_Invoice] [int] NULL,
	[fk_Date_Due] [int] NULL,
	[fk_Date_Paid] [int] NULL,
	[fk_Date_Created] [int] NULL,
	[Invoice_ID] [int] NULL,
	[Treatment_Plan_Item_ID] [int] NULL,
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
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO




