/****** Object:  Table [Silver].[Patients]    Script Date: 20/04/2026 10:15:06 ******/
-- Data-minimised patient table (V011, 2026-06-17). Special-category and excess-
-- identifier fields removed (Title/Middle name, DOB, Gender, Ethnicity, NHS/NI/PPS
-- numbers, phone country codes, Work phone, full Address, Custom fields, Status,
-- Recalls flag, Medical Alert, SMS/Email comms flags, Archived reason, Consent to
-- share, Family ID, Emergency Contact x3, Preferred phone). Retained: identity-for-
-- contact (names + preferred name, mobile/home phone, email), marketing consent,
-- and non-sensitive operational analytics (active, recall dates, acquisition,
-- payment plan, site/practitioner). See DPIA.md sec 7.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Silver].[Patients]
GO
CREATE TABLE [Silver].[Patients](
	[Tenant_ID] [int] NOT NULL,
	[Patient_ID] [int] NOT NULL,
	[Account_ID] [int] NULL,
	[Site_ID] [VARCHAR](50) NULL,
	[Active] [bit] NULL,
	[First_Name] [VARCHAR](100) NULL,
	[Last_Name] [VARCHAR](100) NULL,
	[Preferred_Name] [VARCHAR](100) NULL,
	[Email_Address] [VARCHAR](255) NULL,
	[Mobile_Phone] [VARCHAR](50) NULL,
	[Home_Phone] [VARCHAR](50) NULL,
	[Marketing_Opt_In] [bit] NULL,
	[Dentist_Practitioner_ID] [int] NULL,
	[Hygienist_Practitioner_ID] [int] NULL,
	[Payment_Plan_ID] [int] NULL,
	[Acquisition_Source_ID] [VARCHAR](50) NULL,
	[Dentist_Recall_Date] [date] NULL,
	[Dentist_Recall_Interval] [int] NULL,
	[Hygienist_Recall_Date] [date] NULL,
	[Hygienist_Recall_Interval] [int] NULL,
	[Recall_Method] [VARCHAR](20) NULL,
	[Created_At] [VARCHAR](50) NULL,
	[Updated_At] [VARCHAR](50) NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL,
	[_Row_Hash] [varbinary](32) NULL
)
GO
