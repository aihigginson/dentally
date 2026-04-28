/****** Object:  View [PBI].[List Treatment Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[List Treatment Plans]
GO
CREATE   VIEW [PBI].[List Treatment Plans] AS
SELECT [pk_Treatment_Plan] AS [pk Treatment Plan], [Treatment_Plan_ID] AS [Treatment Plan ID], [Nickname] AS [Nickname], [Patient_ID] AS [Patient ID], [Practitioner_ID] AS [Practitioner ID], [Completed] AS [Completed], [Start_Date] AS [Start Date], [End_Date] AS [End Date], [Completed_Date] AS [Completed Date], [Last_Completed_Date] AS [Last Completed Date], [NHS_UDA_Value] AS [NHS UDA Value], [NHS_Completed_UDA_Value] AS [NHS Completed UDA Value], [Private_Treatment_Value] AS [Private Treatment Value], [Created_Date] AS [Created Date], [Updated_Date] AS [Updated Date], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Dim_Treatment_Plans];
GO
