/****** Object:  Table [Silver].[Payments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Payments]
GO
CREATE TABLE [Silver].[Payments](
	[Payment_Id] [int] NOT NULL,
	[Account_Id] [int] NULL,
	[Patient_Id] [int] NULL,
	[Practitioner_Id] [int] NULL,
	[Payment_Plan_Id] [int] NULL,
	[Site_Id] [VARCHAR](50) NULL,
	[User_Id] [int] NULL,
	[Reference] [VARCHAR](50) NULL,
	[Transaction_Number] [VARCHAR](50) NULL,
	[Amount] [decimal](18, 4) NULL,
	[Amount_Unexplained] [decimal](18, 4) NULL,
	[Method] [VARCHAR](100) NULL,
	[Fully_Explained] [bit] NULL,
	[Deleted] [bit] NULL,
	[Status] [VARCHAR](50) NULL,
	[Dated_On] [date] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
