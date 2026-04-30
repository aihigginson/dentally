/****** Object:  Table [Bronze].[Payment_Explanations]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Payment_Explanations]
GO
CREATE TABLE [Bronze].[Payment_Explanations](
	[ID] [varchar](255) NULL,
	[Amount] [decimal](18, 4) NULL,
	[Comments] [varchar](4000) NULL,
	[Invoice_ID] [int] NULL,
	[Invoice_Reference] [varchar](4000) NULL,
	[Payment_ID] [int] NULL,
	[Payment_Reference] [varchar](4000) NULL,
	[User_ID] [int] NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
