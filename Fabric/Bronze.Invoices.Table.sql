/****** Object:  Table [Bronze].[Invoices]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Invoices]
GO
CREATE TABLE [Bronze].[Invoices](
	[ID] [int] NULL,
	[Amount] [decimal](18, 4) NULL,
	[Amount_Outstanding] [decimal](18, 4) NULL,
	[Dated_On] [VARCHAR](255) NULL,
	[Due_On] [VARCHAR](255) NULL,
	[Reference] [VARCHAR](255) NULL,
	[Paid] [VARCHAR](255) NULL,
	[Paid_On] [VARCHAR](255) NULL,
	[Footnote] [VARCHAR](255) NULL,
	[NHS_Amount] [VARCHAR](255) NULL,
	[Payment_Terms] [VARCHAR](255) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Sent_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Account_ID] [int] NULL,
	[Patient_ID] [int] NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[User_ID] [int] NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
