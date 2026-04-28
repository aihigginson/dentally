/****** Object:  View [PBI].[List Users]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[List Users]
GO
CREATE   VIEW [PBI].[List Users] AS
SELECT [pk_User] AS [pk User], [bk_User_ID] AS [bk User ID], [Title] AS [Title], [First_Name] AS [First Name], [Middle_Name] AS [Middle Name], [Last_Name] AS [Last Name], [Full_Name] AS [Full Name], [Email] AS [Email], [Mobile_Phone] AS [Mobile Phone], [Role] AS [Role], [Permission_Level] AS [Permission Level], [Practice_ID] AS [Practice ID], [Site_ID] AS [Site ID], [Image_URL] AS [Image URL], [Last_Login_Date] AS [Last Login Date], [Created_Date] AS [Created Date], [Updated_Date] AS [Updated Date], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At], [Is_Current] AS [Is Current]
FROM Gold.[Dim_Users];
GO
