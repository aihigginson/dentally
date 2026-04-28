/****** Object:  View [PBI].[List Practitioners]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[List Practitioners]
GO
CREATE   VIEW [PBI].[List Practitioners] AS
SELECT [pk_Practitioner] AS [pk Practitioner], [Practitioner_ID] AS [Practitioner ID], [User_ID] AS [User ID], [Title] AS [Title], [First_Name] AS [First Name], [Middle_Name] AS [Middle Name], [Last_Name] AS [Last Name], [Full_Name] AS [Full Name], [Email] AS [Email], [Mobile_Phone] AS [Mobile Phone], [Role] AS [Role], [Permission_Level] AS [Permission Level], [Active] AS [Active], [Colour] AS [Colour], [GDC_Number] AS [GDC Number], [NHS_Number] AS [NHS Number], [Site_ID] AS [Site ID], [Default_Contract_ID] AS [Default Contract ID], [Contract_Targets_String] AS [Contract Targets String], [Image_URL] AS [Image URL], [Last_Login_Date] AS [Last Login Date], [Created_Date] AS [Created Date], [Updated_Date] AS [Updated Date], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Dim_Practitioners];
GO
