/****** Object:  View [PBI].[_Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[_Recalls]
GO
CREATE   VIEW [PBI].[_Recalls] AS
SELECT [pk_Recall] AS [pk Recall], [bk_Recall_ID] AS [bk Recall ID], [fk_Patient] AS [fk Patient], [fk_Date_Due] AS [fk Date Due], [fk_Date_Run] AS [fk Date Run], [fk_Date_First_Reminder] AS [fk Date First Reminder], [fk_Date_Second_Reminder] AS [fk Date Second Reminder], [fk_Date_Last_Reminded] AS [fk Date Last Reminded], [Appointment_ID] AS [Appointment ID], [Recall_Type] AS [Recall Type], [Recall_Method] AS [Recall Method], [Status] AS [Status], [Workflow_Status] AS [Workflow Status], [Workflow_Stage_ID] AS [Workflow Stage ID], [First_Reminder_Type] AS [First Reminder Type], [Second_Reminder_Type] AS [Second Reminder Type], [Latest_Reminder_Type] AS [Latest Reminder Type], [Times_Contacted] AS [Times Contacted], [Due_Date] AS [Due Date], [Run_Date] AS [Run Date], [Days_Overdue] AS [Days Overdue], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Fact_Recalls];
GO
