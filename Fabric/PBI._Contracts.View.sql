/****** Object:  View [PBI].[_Contracts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[_Contracts]
GO
CREATE   VIEW [PBI].[_Contracts] AS
SELECT [pk_Contract] AS [pk Contract], [bk_Contract_ID] AS [bk Contract ID], [fk_Practice_Site] AS [fk Practice Site], [fk_Date_Start] AS [fk Date Start], [fk_Date_End] AS [fk Date End], [Contract_Number] AS [Contract Number], [NHS_Location_ID] AS [NHS Location ID], [NHS_Site_ID] AS [NHS Site ID], [Site_ID] AS [Site ID], [Active] AS [Active], [PDS_Plus] AS [PDS Plus], [Start_Date] AS [Start Date], [End_Date] AS [End Date], [UDA_Target] AS [UDA Target], [UDA_Value] AS [UDA Value], [UOA_Target] AS [UOA Target], [UOA_Value] AS [UOA Value], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Fact_Contracts];
GO
