/****** Object:  Table [Silver].[Invoices]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Invoices]
GO
CREATE TABLE [Silver].[Invoices](
	[Tenant_ID] [int] NOT NULL,
	[Id] [int] NOT NULL,
	[Account_Id] [int] NULL,
	[Patient_Id] [int] NULL,
	[Site_Id] [VARCHAR](50) NULL,
	[User_Id] [VARCHAR](50) NULL,
	[Reference] [VARCHAR](50) NULL,
	[Amount] [decimal](18, 4) NULL,
	[Amount_Outstanding] [decimal](18, 4) NULL,
	[Nhs_Amount] [decimal](18, 4) NULL,
	[Paid] [bit] NULL,
	[Dated_On] [date] NULL,
	[Due_On] [date] NULL,
	[Paid_On] [date] NULL,
	[Payment_Terms] [VARCHAR](255) NULL,
	[Footnote] [VARCHAR](max) NULL,
	[Sent_At] [datetime2](3) NULL,
	[Status] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
