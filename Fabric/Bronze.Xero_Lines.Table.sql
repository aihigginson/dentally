/****** Object:  Table [Bronze].[Xero_Lines]  ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Xero_Lines]
GO
CREATE TABLE [Bronze].[Xero_Lines](
	[Tenant_ID] [int] NULL,
	[Xero_Tenant_ID] [varchar](100) NULL,
	[Source] [varchar](30) NULL,
	[Doc_ID] [varchar](100) NULL,
	[Doc_Number] [varchar](100) NULL,
	[Doc_Type] [varchar](30) NULL,
	[Doc_Status] [varchar](30) NULL,
	[Doc_Date] [varchar](30) NULL,
	[Contact_Name] [varchar](255) NULL,
	[Line_Amount_Types] [varchar](30) NULL,
	[Line_Item_ID] [varchar](100) NULL,
	[Account_Code] [varchar](50) NULL,
	[Account_ID] [varchar](100) NULL,
	[Description] [varchar](500) NULL,
	[Line_Amount] [decimal](18, 4) NULL,
	[Tax_Amount] [decimal](18, 4) NULL,
	[Tracking] [varchar](500) NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
