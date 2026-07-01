/****** Object:  Table [Silver].[Xero_Finance_Lines]  ******/
-- One row per P&L-affecting transaction line (invoices, credit notes, bank
-- transactions, manual journals). PL_Amount is the signed P&L contribution
-- (revenue +, expense +; net profit = revenue - expense). Holds ALL periods --
-- date filtering is a reporting concern, not applied here.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Xero_Finance_Lines]
GO
CREATE TABLE [Silver].[Xero_Finance_Lines](
	[Tenant_ID] [int] NULL,
	[Xero_Tenant_ID] [varchar](100) NULL,
	[Source] [varchar](30) NULL,
	[Doc_ID] [varchar](100) NULL,
	[Doc_Number] [varchar](100) NULL,
	[Doc_Type] [varchar](30) NULL,
	[Doc_Status] [varchar](30) NULL,
	[Doc_Date] [date] NULL,
	[Contact_Name] [varchar](255) NULL,
	[Account_ID] [varchar](100) NULL,
	[Account_Code] [varchar](50) NULL,
	[Account_Class] [varchar](50) NULL,
	[PL_Group] [varchar](30) NULL,
	[Description] [varchar](500) NULL,
	[Net_Amount] [decimal](18, 4) NULL,     -- ex-tax line amount
	[PL_Amount] [decimal](18, 4) NULL,      -- signed P&L contribution
	[Line_Item_ID] [varchar](100) NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
