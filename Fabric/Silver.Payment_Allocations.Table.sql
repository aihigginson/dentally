/****** Object:  Table [Silver].[Payment_Allocations]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Payment_Allocations]
GO
CREATE TABLE [Silver].[Payment_Allocations](
	[Tenant_ID] [int] NOT NULL,
	[Payment_Allocation_ID] [VARCHAR](50) NOT NULL,
	[Patient_ID] [int] NULL,
	[Payment_Explanation_ID] [int] NULL,
	[Invoice_Item_ID] [VARCHAR](50) NULL,
	[Reversal_Of_ID] [VARCHAR](50) NULL,
	[Amount] [decimal](18, 4) NULL,
	[Description] [VARCHAR](500) NULL,
	[Transfer_From_ID] [VARCHAR](50) NULL,
	[Transfer_From_Type] [VARCHAR](50) NULL,
	[Transfer_To_ID] [VARCHAR](50) NULL,
	[Transfer_To_Type] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
