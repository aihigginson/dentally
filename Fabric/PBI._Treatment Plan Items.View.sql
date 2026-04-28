/****** Object:  View [PBI].[_Treatment Plan Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[_Treatment Plan Items]
GO
CREATE   VIEW [PBI].[_Treatment Plan Items] AS
SELECT [pk_Treatment_Plan_Item] AS [pk Treatment Plan Item], [bk_Treatment_Plan_Item_ID] AS [bk Treatment Plan Item ID], [fk_Treatment_Plan] AS [fk Treatment Plan], [fk_Patient] AS [fk Patient], [fk_Practitioner] AS [fk Practitioner], [fk_Payment_Plan] AS [fk Payment Plan], [fk_Treatment] AS [fk Treatment], [fk_Date_Created] AS [fk Date Created], [fk_Date_Completed] AS [fk Date Completed], [fk_Date_Updated] AS [fk Date Updated], [Treatment_Plan_ID] AS [Treatment Plan ID], [Invoice_ID] AS [Invoice ID], [Treatment_Appointment_ID] AS [Treatment Appointment ID], [Referrer_ID] AS [Referrer ID], [Nomenclature] AS [Nomenclature], [Patient_Nomenclature] AS [Patient Nomenclature], [NHS_Treatment_Cat] AS [NHS Treatment Cat], [UDA_Band] AS [UDA Band], [Region] AS [Region], [Notes] AS [Notes], [Position] AS [Position], [Base_Chart] AS [Base Chart], [Completed] AS [Completed], [Charged] AS [Charged], [Appear_On_Invoice] AS [Appear On Invoice], [Price] AS [Price], [Duration_Mins] AS [Duration Mins], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Fact_Treatment_Plan_Items];
GO
