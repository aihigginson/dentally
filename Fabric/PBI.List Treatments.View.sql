/****** Object:  View [PBI].[List Treatments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[List Treatments]
GO
CREATE   VIEW [PBI].[List Treatments] AS
SELECT [pk_Treatment] AS [pk Treatment], [Treatment_ID] AS [Treatment ID], [Treatment_Code] AS [Treatment Code], [Nomenclature] AS [Nomenclature], [Patient_Nomenclature] AS [Patient Nomenclature], [Description] AS [Description], [Patient_Description] AS [Patient Description], [Notes] AS [Notes], [Region] AS [Region], [UDA_Band] AS [UDA Band], [NHS_Treatment_Cat] AS [NHS Treatment Cat], [Treatment_Category_ID] AS [Treatment Category ID], [Treatment_Category_Name] AS [Treatment Category Name], [Created_Date] AS [Created Date], [Updated_Date] AS [Updated Date], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Dim_Treatments];
GO
