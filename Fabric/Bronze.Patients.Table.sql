/****** Object:  Table [Bronze].[Patients]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Patients]
GO
CREATE TABLE [Bronze].[Patients](
	[Patient_ID] [decimal](18, 4) NULL,
	[Account_ID] [decimal](18, 4) NULL,
	[Active] [decimal](18, 4) NULL,
	[Acquisition_Source_ID] [VARCHAR](255) NULL,
	[Address_Line_1] [VARCHAR](255) NULL,
	[Address_Line_2] [VARCHAR](255) NULL,
	[County] [VARCHAR](255) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Custom_Field_1] [VARCHAR](255) NULL,
	[Custom_Field_2] [VARCHAR](255) NULL,
	[Date_Of_Birth] [VARCHAR](255) NULL,
	[Dentist_ID] [decimal](18, 4) NULL,
	[Dentist_Recall_Date] [VARCHAR](255) NULL,
	[Dentist_Recall_Interval] [decimal](18, 4) NULL,
	[Email_Address] [VARCHAR](255) NULL,
	[Ethnicity] [decimal](18, 4) NULL,
	[Family_ID] [VARCHAR](255) NULL,
	[First_Name] [VARCHAR](255) NULL,
	[Gender] [decimal](18, 4) NULL,
	[Home_Phone] [VARCHAR](255) NULL,
	[Home_Phone_Country] [VARCHAR](255) NULL,
	[Hygienist_ID] [decimal](18, 4) NULL,
	[Hygienist_Recall_Date] [VARCHAR](255) NULL,
	[Hygienist_Recall_Interval] [decimal](18, 4) NULL,
	[Image_Url] [VARCHAR](255) NULL,
	[Last_Name] [VARCHAR](255) NULL,
	[Legacy_ID] [VARCHAR](255) NULL,
	[Marketing] [VARCHAR](255) NULL,
	[Medical_Alert] [decimal](18, 4) NULL,
	[Medical_Alert_Text] [VARCHAR](255) NULL,
	[Middle_Name] [VARCHAR](255) NULL,
	[Mobile_Phone] [VARCHAR](255) NULL,
	[Mobile_Phone_Country] [VARCHAR](255) NULL,
	[NHS_Number] [VARCHAR](255) NULL,
	[Ni_Number] [VARCHAR](255) NULL,
	[Occupation] [VARCHAR](255) NULL,
	[Payment_Plan_ID] [int] NULL,
	[Postcode] [VARCHAR](255) NULL,
	[Preferred_Name] [VARCHAR](255) NULL,
	[Preferred_Phone_Number] [decimal](18, 4) NULL,
	[Recall_Method] [VARCHAR](255) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Title] [VARCHAR](255) NULL,
	[Town] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Use_Email] [decimal](18, 4) NULL,
	[Use_Sms] [decimal](18, 4) NULL,
	[Work_Phone] [VARCHAR](255) NULL,
	[Work_Phone_Country] [VARCHAR](255) NULL
)
GO
