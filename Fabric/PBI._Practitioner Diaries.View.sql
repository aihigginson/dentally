/****** Object:  View [PBI].[_Practitioner Diaries]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[_Practitioner Diaries]
GO
CREATE   VIEW [PBI].[_Practitioner Diaries] AS
SELECT [pk_Practitioner_Diary] AS [pk Practitioner Diary], [bk_Practitioner_Diary_ID] AS [bk Practitioner Diary ID], [fk_Practitioner] AS [fk Practitioner], [fk_Date_Day] AS [fk Date Day], [Day_Date] AS [Day Date], [Start_Time] AS [Start Time], [End_Time] AS [End Time], [Unavailable] AS [Unavailable], [Session_Duration_Mins] AS [Session Duration Mins], [Total_Break_Mins] AS [Total Break Mins], [Available_Clinical_Mins] AS [Available Clinical Mins], [Break_Count] AS [Break Count], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Fact_Practitioner_Diaries];
GO
