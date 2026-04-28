/****** Object:  Table [Silver].[Fees]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Fees]
GO
CREATE TABLE [Silver].[Fees](
	[Fee_Id] [uniqueidentifier] NOT NULL,
	[Treatment_Id] [int] NULL,
	[Payment_Plan_Id] [int] NULL,
	[Price] [decimal](18, 4) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
