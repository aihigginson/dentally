/****** Object:  View [PBI].[List Payment Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[List Payment Plans]
GO
CREATE   VIEW [PBI].[List Payment Plans] AS
SELECT [pk_Payment_Plan] AS [pk Payment Plan], [Payment_Plan_ID] AS [Payment Plan ID], [Payment_Plan_Name] AS [Payment Plan Name], [Patient_Friendly_Name] AS [Patient Friendly Name], [Active] AS [Active], [Colour] AS [Colour], [Site_ID] AS [Site ID], [Dentist_Recall_Interval_Months] AS [Dentist Recall Interval Months], [Hygienist_Recall_Interval_Months] AS [Hygienist Recall Interval Months], [Emergency_Duration_Mins] AS [Emergency Duration Mins], [Exam_Duration_Mins] AS [Exam Duration Mins], [Exam_Scale_Polish_Duration_Mins] AS [Exam Scale Polish Duration Mins], [Scale_Polish_Duration_Mins] AS [Scale Polish Duration Mins], [Created_Date] AS [Created Date], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Dim_Payment_Plans];
GO
