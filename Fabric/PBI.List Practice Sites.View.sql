/****** Object:  View [PBI].[List Practice Sites]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[List Practice Sites]
GO
CREATE   VIEW [PBI].[List Practice Sites] AS
SELECT [pk_Practice_Site] AS [pk Practice Site], [Site_ID] AS [Site ID], [Site_Name] AS [Site Name], [Site_Active] AS [Site Active], [Site_Address_Line_1] AS [Site Address Line 1], [Site_Address_Line_2] AS [Site Address Line 2], [Site_Town] AS [Site Town], [Site_Postcode] AS [Site Postcode], [Site_Phone] AS [Site Phone], [Site_Website] AS [Site Website], [Site_Logo_URL] AS [Site Logo URL], [Site_Default_Payment_Plan_ID] AS [Site Default Payment Plan ID], [Mon_Open] AS [Mon Open], [Mon_Close] AS [Mon Close], [Tue_Open] AS [Tue Open], [Tue_Close] AS [Tue Close], [Wed_Open] AS [Wed Open], [Wed_Close] AS [Wed Close], [Thu_Open] AS [Thu Open], [Thu_Close] AS [Thu Close], [Fri_Open] AS [Fri Open], [Fri_Close] AS [Fri Close], [Practice_ID] AS [Practice ID], [Practice_Name] AS [Practice Name], [Practice_Address_Line_1] AS [Practice Address Line 1], [Practice_Address_Line_2] AS [Practice Address Line 2], [Practice_Town] AS [Practice Town], [Practice_Postcode] AS [Practice Postcode], [Practice_Phone] AS [Practice Phone], [Practice_Email] AS [Practice Email], [Practice_Website] AS [Practice Website], [Practice_NHS] AS [Practice NHS], [Practice_Time_Zone] AS [Practice Time Zone], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Dim_Practice_Sites];
GO
