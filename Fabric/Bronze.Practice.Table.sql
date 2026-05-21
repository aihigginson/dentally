/****** Object:  Table [Bronze].[Practice]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Practice]
GO
CREATE TABLE [Bronze].[Practice](
	[Practice_ID] [VARCHAR](255) NULL,
	[Address_Line_1] [VARCHAR](255) NULL,
	[Address_Line_2] [VARCHAR](255) NULL,
	[Custom_Patient_Field_Label_1] [VARCHAR](255) NULL,
	[Custom_Patient_Field_Label_2] [VARCHAR](255) NULL,
	[Email_Address] [VARCHAR](255) NULL,
	[Logo_Url] [VARCHAR](255) NULL,
	[Medical_History_Expiry_Days] [decimal](18, 4) NULL,
	[Practice_Name] [VARCHAR](255) NULL,
	[NHS] [decimal](18, 4) NULL,
	[Oh_Mon#close] [VARCHAR](255) NULL,
	[Oh_Mon#open] [VARCHAR](255) NULL,
	[Oh_Tues#close] [VARCHAR](255) NULL,
	[Oh_Tues#open] [VARCHAR](255) NULL,
	[Oh_Wed#close] [VARCHAR](255) NULL,
	[Oh_Wed#open] [VARCHAR](255) NULL,
	[Oh_Thur#close] [VARCHAR](255) NULL,
	[Oh_Thur#open] [VARCHAR](255) NULL,
	[Oh_Fri#close] [VARCHAR](255) NULL,
	[Oh_Fri#open] [VARCHAR](255) NULL,
	[Oh_Sat#close] [VARCHAR](255) NULL,
	[Oh_Sat#open] [VARCHAR](255) NULL,
	[Oh_Sun#close] [VARCHAR](255) NULL,
	[Oh_Sun#open] [VARCHAR](255) NULL,
	[Patient_Email_Address] [VARCHAR](255) NULL,
	[Phone_Number] [VARCHAR](255) NULL,
	[Postcode] [VARCHAR](255) NULL,
	[Slug] [VARCHAR](255) NULL,
	[Time_Zone] [VARCHAR](255) NULL,
	[Town] [VARCHAR](255) NULL,
	[Website] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
