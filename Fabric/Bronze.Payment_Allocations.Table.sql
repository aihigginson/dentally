/****** Object:  Table [Bronze].[Payment_Allocations]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Payment_Allocations]
GO
CREATE TABLE [Bronze].[Payment_Allocations](
	[ID] [VARCHAR](255) NULL,
	[Amount] [decimal](18, 4) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Description] [VARCHAR](255) NULL,
	[Invoice_Item_ID] [VARCHAR](255) NULL,
	[Patient_ID] [decimal](18, 4) NULL,
	[Payment_Explanation_ID] [decimal](18, 4) NULL,
	[Reversal_Of_ID] [VARCHAR](255) NULL,
	[Transfer_From_ID] [VARCHAR](255) NULL,
	[Transfer_From_Type] [VARCHAR](255) NULL,
	[Transfer_To_ID] [VARCHAR](255) NULL,
	[Transfer_To_Type] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
