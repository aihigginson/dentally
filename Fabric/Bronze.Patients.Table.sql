/****** Object:  Table [Bronze].[Patients]    Script Date: 20/04/2026 10:15:06 ******/
-- Data-minimised patient table (V011, 2026-06-17). Special-category and excess-
-- identifier fields are no longer landed in the warehouse (Title/Middle name, DOB,
-- Gender, Ethnicity, NHS/NI numbers, phone country codes, Work phone, Address,
-- Custom/Legacy fields, Occupation, Image URL, Medical Alert, Archived reason,
-- Emergency Contact x3, Work phone). Retained: identity-for-contact (names +
-- preferred name, mobile/home phone, email), the contact-preference fields
-- (Use_Email / Use_SMS / Preferred_Phone, re-added V015), marketing flag +
-- operational analytics. See DPIA.md sec 7.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Bronze].[Patients]
GO
CREATE TABLE [Bronze].[Patients](
	[Patient_ID] [decimal](18, 4) NULL,
	[Account_ID] [decimal](18, 4) NULL,
	[Active] [VARCHAR](255) NULL,
	[Acquisition_Source_ID] [VARCHAR](255) NULL,
	[Created_At] [VARCHAR](255) NULL,
	[Dentist_ID] [decimal](18, 4) NULL,
	[Dentist_Recall_Date] [VARCHAR](255) NULL,
	[Dentist_Recall_Interval] [decimal](18, 4) NULL,
	[Email_Address] [VARCHAR](255) NULL,
	[First_Name] [VARCHAR](255) NULL,
	[Home_Phone] [VARCHAR](255) NULL,
	[Hygienist_ID] [decimal](18, 4) NULL,
	[Hygienist_Recall_Date] [VARCHAR](255) NULL,
	[Hygienist_Recall_Interval] [decimal](18, 4) NULL,
	[Last_Name] [VARCHAR](255) NULL,
	[Marketing] [VARCHAR](255) NULL,
	[Mobile_Phone] [VARCHAR](255) NULL,
	[Use_Email] [VARCHAR](255) NULL,
	[Use_SMS] [VARCHAR](255) NULL,
	[Preferred_Phone] [VARCHAR](255) NULL,
	[Payment_Plan_ID] [int] NULL,
	[Preferred_Name] [VARCHAR](255) NULL,
	[Recall_Method] [VARCHAR](255) NULL,
	[Site_ID] [VARCHAR](255) NULL,
	[Updated_At] [VARCHAR](255) NULL,
	[Tenant_ID] [int] NULL,
	[DW_Loaded_At] [datetime2](3) NULL
)
GO
