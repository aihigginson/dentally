/****** Object:  Table [Silver].[Invoice_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Invoice_Items]
GO
CREATE TABLE [Silver].[Invoice_Items](
	[Tenant_ID] [int] NOT NULL,
	[Id] [VARCHAR](50) NOT NULL,
	[Invoice_ID] [int] NULL,
	[Practitioner_ID] [int] NULL,
	[Treatment_Plan_ID] [int] NULL,
	[Treatment_Plan_Item_ID] [VARCHAR](50) NULL,
	[Sundry_ID] [VARCHAR](255) NULL,
	[User_ID] [VARCHAR](255) NULL,
	[Name] [VARCHAR](255) NULL,
	[Quantity] [int] NULL,
	[Item_Price] [decimal](18, 4) NULL,
	[Total_Price] [decimal](18, 4) NULL,
	[NHS_Charge] [bit] NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
