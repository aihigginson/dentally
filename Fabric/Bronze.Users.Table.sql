/****** Object:  Table [Bronze].[Users]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Users]
GO
CREATE TABLE [Bronze].[Users](
	[ID] [decimal](18, 4) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Email] [VARCHAR](255) NULL,
	[First_Name] [VARCHAR](255) NULL,
	[Image_Url] [VARCHAR](255) NULL,
	[Last_Login] [VARCHAR](255) NULL,
	[Last_Name] [VARCHAR](255) NULL,
	[Middle_Name] [VARCHAR](255) NULL,
	[Mobile_Phone] [VARCHAR](255) NULL,
	[Permission_Level] [decimal](18, 4) NULL,
	[Practice_ID] [VARCHAR](255) NULL,
	[Role] [VARCHAR](255) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Title] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL
)
GO
