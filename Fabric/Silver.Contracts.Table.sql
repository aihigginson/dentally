/****** Object:  Table [Silver].[Contracts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Contracts]
GO
CREATE TABLE [Silver].[Contracts](
	[Tenant_ID] [int] NOT NULL,
	[Id] [VARCHAR](50) NOT NULL,
	[Site_Id] [VARCHAR](50) NULL,
	[Active] [bit] NULL,
	[Contract_Number] [VARCHAR](50) NULL,
	[Name] [VARCHAR](255) NULL,
	[Nhs_Location_Id] [VARCHAR](50) NULL,
	[Nhs_Site_Id] [VARCHAR](50) NULL,
	[Notes] [VARCHAR](max) NULL,
	[Pds_Plus] [bit] NULL,
	[Start_Date] [date] NULL,
	[End_Date] [date] NULL,
	[Target] [decimal](18, 4) NULL,
	[Uda_Value] [decimal](18, 4) NULL,
	[Uoa_Target] [decimal](18, 4) NULL,
	[Uoa_Value] [decimal](18, 4) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL,
	[_Raw_Json] [VARCHAR](max) NULL
)
GO
