/****** Object:  Table [Silver].[Practitioners]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Practitioners]
GO
CREATE TABLE [Silver].[Practitioners](
	[Tenant_ID] [int] NOT NULL,
	[Practitioner_Id] [int] NOT NULL,
	[User_Id] [int] NULL,
	[Site_Id] [VARCHAR](50) NULL,
	[User_Title] [VARCHAR](50) NULL,
	[User_First_Name] [VARCHAR](100) NULL,
	[User_Middle_Name] [VARCHAR](100) NULL,
	[User_Last_Name] [VARCHAR](100) NULL,
	[User_Email] [VARCHAR](100) NULL,
	[User_Mobile_Phone] [VARCHAR](100) NULL,
	[User_Role] [VARCHAR](100) NULL,
	[User_Permission_Level] [int] NULL,
	[Practitioner_Active] [int] NULL,
	[Practitioner_Colour] [VARCHAR](100) NULL,
	[Practitioner_GDC_Number] [VARCHAR](100) NULL,
	[Practitioner_NHS_Number] [VARCHAR](100) NULL,
	[Practitioner_Site_Id] [VARCHAR](100) NULL,
	[Practitioner_Default_Contract_Id] [VARCHAR](100) NULL,
	[Contract_Targets_String] [VARCHAR](100) NULL,
	[User_Image_URL] [VARCHAR](100) NULL,
	[User_Last_Login] [VARCHAR](100) NULL,
	[User_Created_At] [VARCHAR](100) NULL,
	[User_Updated_At] [VARCHAR](100) NULL,
	[Performer_Id] [VARCHAR](50) NULL,
	[Dentist_Type] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
