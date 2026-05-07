/****** Object:  Table [Gold].[Dim_Practice_Sites]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Practice_Sites]
GO
CREATE TABLE [Gold].[Dim_Practice_Sites](
	[pk_Practice_Site] [bigint] NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[Site_ID] [VARCHAR](50) NOT NULL,
	[Site_Name] [VARCHAR](255) NULL,
	[Site_Active] [bit] NULL,
	[Site_Address_Line_1] [VARCHAR](255) NULL,
	[Site_Address_Line_2] [VARCHAR](255) NULL,
	[Site_Town] [VARCHAR](100) NULL,
	[Site_Postcode] [VARCHAR](20) NULL,
	[Site_Phone] [VARCHAR](50) NULL,
	[Site_Website] [VARCHAR](255) NULL,
	[Site_Logo_URL] [VARCHAR](255) NULL,
	[Site_Default_Payment_Plan_ID] [int] NULL,
	[Mon_Open] [time](0) NULL,
	[Mon_Close] [time](0) NULL,
	[Tue_Open] [time](0) NULL,
	[Tue_Close] [time](0) NULL,
	[Wed_Open] [time](0) NULL,
	[Wed_Close] [time](0) NULL,
	[Thu_Open] [time](0) NULL,
	[Thu_Close] [time](0) NULL,
	[Fri_Open] [time](0) NULL,
	[Fri_Close] [time](0) NULL,
	[Practice_ID] [VARCHAR](255) NULL,
	[Practice_Name] [VARCHAR](255) NULL,
	[Practice_Address_Line_1] [VARCHAR](255) NULL,
	[Practice_Address_Line_2] [VARCHAR](255) NULL,
	[Practice_Town] [VARCHAR](100) NULL,
	[Practice_Postcode] [VARCHAR](20) NULL,
	[Practice_Phone] [VARCHAR](50) NULL,
	[Practice_Email] [VARCHAR](255) NULL,
	[Practice_Website] [VARCHAR](255) NULL,
	[Practice_NHS] [bit] NULL,
	[Practice_Time_Zone] [VARCHAR](100) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO
