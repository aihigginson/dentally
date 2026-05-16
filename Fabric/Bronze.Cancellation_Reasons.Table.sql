/****** Object:  Table [Bronze].[Cancellation_Reasons]    Script Date: 15/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Cancellation_Reasons]
GO
CREATE TABLE [Bronze].[Cancellation_Reasons](
	[ID] [VARCHAR](255) NULL,
	[Active] [int] NULL,
	[Name] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
