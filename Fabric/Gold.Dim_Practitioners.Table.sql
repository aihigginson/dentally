/****** Object:  Table [Gold].[Dim_Practitioners]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Practitioners]
GO
CREATE TABLE [Gold].[Dim_Practitioners](
	[pk_Practitioner] [bigint] NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[Practitioner_ID] [int] NOT NULL,
	[User_ID] [int] NULL,
	[Title] [VARCHAR](50) NULL,
	[First_Name] [VARCHAR](100) NULL,
	[Middle_Name] [VARCHAR](100) NULL,
	[Last_Name] [VARCHAR](100) NULL,
	[Full_Name] [VARCHAR](255) NULL,
	[Email] [VARCHAR](255) NULL,
	[Mobile_Phone] [VARCHAR](50) NULL,
	[Role] [VARCHAR](100) NULL,
	[Custom_Role] [varchar](100) NULL,
	[FTE] [DECIMAL](4,2) NULL,
	[Permission_Level] [int] NULL,
	[Active] [bit] NULL,
	[Colour] [VARCHAR](50) NULL,
	[GDC_Number] [VARCHAR](50) NULL,
	[NHS_Number] [VARCHAR](50) NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[Default_Contract_ID] [VARCHAR](255) NULL,
	[Contract_Targets_String] [VARCHAR](255) NULL,
	[Image_URL] [VARCHAR](255) NULL,
	[Last_Login_Date] [date] NULL,
	[Created_Date] [datetime2](3) NULL,
	[Updated_Date] [datetime2](3) NULL,
	[Practitioner_Count] [int] NOT NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO
