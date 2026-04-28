/****** Object:  View [PBI].[_Treatment Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[_Treatment Appointments]
GO
CREATE   VIEW [PBI].[_Treatment Appointments] AS
SELECT [pk_Treatment_Appointment] AS [pk Treatment Appointment], [bk_Treatment_Appointment_ID] AS [bk Treatment Appointment ID], [fk_Patient] AS [fk Patient], [fk_Treatment_Plan] AS [fk Treatment Plan], [fk_Date_Appointment] AS [fk Date Appointment], [fk_Date_Created] AS [fk Date Created], [Appointment_ID] AS [Appointment ID], [Treatment_Plan_ID] AS [Treatment Plan ID], [Position] AS [Position], [Bookable] AS [Bookable], [Notes] AS [Notes], [Created_At] AS [Created At], [Updated_At] AS [Updated At], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Fact_Treatment_Appointments];
GO
