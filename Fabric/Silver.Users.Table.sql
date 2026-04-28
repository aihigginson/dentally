/****** Object:  Table [Silver].[Users]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Users]
GO
CREATE TABLE [Silver].[Users](
	[Id] [int] NOT NULL,
	[Email] [VARCHAR](255) NULL,
	[Title] [VARCHAR](100) NULL,
	[First_Name] [VARCHAR](100) NULL,
	[Middle_Name] [VARCHAR](100) NULL,
	[Last_Name] [VARCHAR](100) NULL,
	[Mobile_Phone] [VARCHAR](100) NULL,
	[Role] [VARCHAR](100) NULL,
	[Permission_Level] [int] NULL,
	[Practice_Id] [VARCHAR](100) NULL,
	[Site_Id] [VARCHAR](100) NULL,
	[Image_URL] [VARCHAR](100) NULL,
	[Last_Login] [VARCHAR](100) NULL,
	[Created_At] [VARCHAR](100) NULL,
	[Updated_At] [VARCHAR](100) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
