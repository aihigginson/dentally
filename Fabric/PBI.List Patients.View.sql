/****** Object:  View [PBI].[List Patients]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP VIEW IF EXISTS [PBI].[List Patients]
GO
CREATE   VIEW [PBI].[List Patients] AS
SELECT [pk_Patient] AS [pk Patient], [Patient_ID] AS [Patient ID], [Account_ID] AS [Account ID], [Title] AS [Title], [First_Name] AS [First Name], [Middle_Name] AS [Middle Name], [Last_Name] AS [Last Name],
[Preferred_Name] AS [Preferred Name], [Full_Name] AS [Full Name], [Date_Of_Birth] AS [Date Of Birth], [Age_Years] AS [Age Years], [Gender_Code] AS [Gender Code], [Gender_Description] AS [Gender Description], 
[Ethnicity_Code] AS [Ethnicity Code], [NHS_Number] AS [NHS Number], [NI_Number] AS [NI Number], [Email_Address] AS [Email Address], [Home_Phone] AS [Home Phone], [Mobile_Phone] AS [Mobile Phone],
[Work_Phone] AS [Work Phone], [Address_Line_1] AS [Address Line 1], [Address_Line_2] AS [Address Line 2], [Town] AS [Town], [County] AS [County], [Postcode] AS [Postcode], [Active] AS [Active],
[Medical_Alert] AS [Medical Alert], [Medical_Alert_Text] AS [Medical Alert Text], [Payment_Plan_ID] AS [Payment Plan ID], [Site_ID] AS [Site ID], [Family_ID] AS [Family ID], 
[Acquisition_Source_ID] AS [Acquisition Source ID], [Dentist_Practitioner_ID] AS [Dentist Practitioner ID], [Hygienist_Practitioner_ID] AS [Hygienist Practitioner ID], 
 [Dentist_Practitioner_ID] AS [Dentist ID], [Hygienist_Practitioner_ID] AS [Hygienist ID], 
[Dentist_Recall_Date] AS [Dentist Recall Date], [Dentist_Recall_Interval_Months] AS [Dentist Recall Interval Months], [Hygienist_Recall_Date] AS [Hygienist Recall Date], [Hygienist_Recall_Interval_Months] AS [Hygienist Recall Interval Months], [Recall_Method] AS [Recall Method], [Preferred_Contact_Method] AS [Preferred Contact Method], [Use_Email] AS [Use Email], [Use_SMS] AS [Use SMS], [Marketing_Consent] AS [Marketing Consent], [Occupation] AS [Occupation], [Legacy_ID] AS [Legacy ID], [Custom_Field_1] AS [Custom Field 1], [Custom_Field_2] AS [Custom Field 2], [First_Appointment_Date] AS [First Appointment Date], [Last_Appointment_Date] AS [Last Appointment Date], [Next_Appointment_Date] AS [Next Appointment Date], [First_Exam_Date] AS [First Exam Date], [Last_Exam_Date] AS [Last Exam Date], [Next_Exam_Date] AS [Next Exam Date], [Last_Scale_Polish_Date] AS [Last Scale Polish Date], [Next_Scale_Polish_Date] AS [Next Scale Polish Date], [Last_FTA_Date] AS [Last FTA Date], [Last_Cancelled_Appointment_Date] AS [Last Cancelled Appointment Date], [Total_Paid] AS [Total Paid], [Total_Invoiced] AS [Total Invoiced], [NHS_Exemption_Code] AS [NHS Exemption Code], [Patient_Created_Date] AS [Patient Created Date], [Patient_Updated_Date] AS [Patient Updated Date], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Dim_Patients];
GO
