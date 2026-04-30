/****** Object:  Table [Bronze].[Fees]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Fees]
GO
CREATE TABLE [Bronze].[Fees](
	[Fee_ID] [VARCHAR](255) NULL,
	[Payment_Plan_ID] [int] NULL,
	[Treatment_ID] [decimal](18, 4) NULL,
	[Multiple_Pricing] [int] NULL,
	[Duration_One] [int] NULL,
	[Duration_Two] [int] NULL,
	[Duration_Three] [int] NULL,
	[Duration_Four] [int] NULL,
	[Duration_Five] [int] NULL,
	[Price_One] [VARCHAR](255) NULL,
	[Price_Two] [VARCHAR](255) NULL,
	[Price_Three] [VARCHAR](255) NULL,
	[Price_Four] [VARCHAR](255) NULL,
	[Price_Five] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
