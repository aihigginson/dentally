/****** Object:  Table [Gold].[Dim_Users]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Users]
GO
CREATE TABLE [Gold].[Dim_Users](
	[pk_User] [bigint] NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[bk_User_ID] [int] NOT NULL,
	[Title] [VARCHAR](50) NULL,
	[First_Name] [VARCHAR](100) NULL,
	[Middle_Name] [VARCHAR](100) NULL,
	[Last_Name] [VARCHAR](100) NULL,
	[Full_Name] [VARCHAR](255) NULL,
	[Email] [VARCHAR](255) NULL,
	[Mobile_Phone] [VARCHAR](50) NULL,
	[Role] [VARCHAR](100) NULL,
	[Permission_Level] [int] NULL,
	[Practice_ID] [VARCHAR](255) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Image_URL] [VARCHAR](255) NULL,
	[Last_Login_Date] [date] NULL,
	[Created_Date] [datetime2](3) NULL,
	[Updated_Date] [datetime2](3) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[Is_Current] [bit] NOT NULL
)
GO
