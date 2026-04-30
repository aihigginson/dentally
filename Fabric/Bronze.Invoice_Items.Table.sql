/****** Object:  Table [Bronze].[Invoice_Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Invoice_Items]
GO
CREATE TABLE [Bronze].[Invoice_Items](
	[ID] [VARCHAR](255) NULL,
	[Item_Price] [int] NULL,
	[Name] [VARCHAR](255) NULL,
	[NHS_Charge] [int] NULL,
	[Quantity] [int] NULL,
	[Total_Price] [decimal](18, 4) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Invoice_ID] [int] NULL,
	[Practitioner_ID] [int] NULL,
	[Sundry_ID] [VARCHAR](255) NULL,
	[Treatment_Plan_ID] [int] NULL,
	[Treatment_Plan_Item_ID] [int] NULL,
	[User_ID] [int] NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
