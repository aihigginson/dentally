/****** Object:  Table [Bronze].[Practitioners]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Practitioners]
GO
CREATE TABLE [Bronze].[Practitioners](
	[Practitioner_ID] [int] NULL,
	[Practitioner_Active] [decimal](18, 4) NULL,
	[Practitioner_Colour] [VARCHAR](255) NULL,
	[Practitioner_Default_Contract_ID] [VARCHAR](255) NULL,
	[Practitioner_Gdc_Number] [VARCHAR](255) NULL,
	[Practitioner_NHS_Number] [VARCHAR](255) NULL,
	[Practitioner_Site_ID] [VARCHAR](255) NULL,
	[User_ID] [int] NULL,
	[User_Created_At] [VARCHAR](255) NULL,
	[User_Email] [VARCHAR](255) NULL,
	[User_First_Name] [VARCHAR](255) NULL,
	[User_Image_Url] [VARCHAR](255) NULL,
	[User_Last_Login] [VARCHAR](255) NULL,
	[User_Last_Name] [VARCHAR](255) NULL,
	[User_Middle_Name] [VARCHAR](255) NULL,
	[User_Mobile_Phone] [VARCHAR](255) NULL,
	[User_Permission_Level] [decimal](18, 4) NULL,
	[User_Role] [VARCHAR](255) NULL,
	[User_Title] [VARCHAR](255) NULL,
	[User_Updated_At] [VARCHAR](255) NULL,
	[Contract_Targets_String] [VARCHAR](MAX) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
