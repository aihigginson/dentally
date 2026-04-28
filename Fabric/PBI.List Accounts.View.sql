/****** Object:  View [PBI].[List Accounts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[List Accounts]
GO
CREATE   VIEW [PBI].[List Accounts] AS
SELECT [pk_Account] AS [pk Account], [Account_ID] AS [Account ID], [Patient_ID] AS [Patient ID], [Patient_Name] AS [Patient Name], [Current_Balance] AS [Current Balance], [Opening_Balance] AS [Opening Balance], [Planned_NHS_Treatment_Value] AS [Planned NHS Treatment Value], [Planned_Private_Treatment_Value] AS [Planned Private Treatment Value], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Dim_Accounts];
GO
