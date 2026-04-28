/****** Object:  View [PBI].[List Date]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[List Date]
GO
CREATE   VIEW [PBI].[List Date] AS
SELECT [pk_Date] AS [pk Date], [Full_Date] AS [Full Date], [Day_Name] AS [Day Name], [Day_Of_Week] AS [Day Of Week], [Day_Of_Month] AS [Day Of Month], [Day_Of_Year] AS [Day Of Year], [Week_Of_Year] AS [Week Of Year], [Week_Of_Month] AS [Week Of Month], [Month_Number] AS [Month Number], [Month_Name] AS [Month Name], [Month_Name_Short] AS [Month Name Short], [Month_Year] AS [Month Year], [Calendar_Quarter] AS [Calendar Quarter], [Calendar_Quarter_Name] AS [Calendar Quarter Name], [Calendar_Year] AS [Calendar Year], [Calendar_Year_Month] AS [Calendar Year Month], [Calendar_Year_Quarter] AS [Calendar Year Quarter], [Relative_Day] AS [Relative Day], [Relative_Week] AS [Relative Week], [Relative_Month] AS [Relative Month], [Relative_Quarter] AS [Relative Quarter], [Relative_Year] AS [Relative Year], [Financial_Year] AS [Financial Year], [Financial_Year_Name] AS [Financial Year Name], [Financial_Quarter] AS [Financial Quarter], [Financial_Quarter_Name] AS [Financial Quarter Name], [Financial_Month] AS [Financial Month], [Financial_Month_Name] AS [Financial Month Name], [Financial_Week] AS [Financial Week], [Financial_Day_Of_Year] AS [Financial Day Of Year], [Relative_Financial_Day] AS [Relative Financial Day], [Relative_Financial_Week] AS [Relative Financial Week], [Relative_Financial_Month] AS [Relative Financial Month], [Relative_Financial_Quarter] AS [Relative Financial Quarter], [Relative_Financial_Year] AS [Relative Financial Year], [Is_Weekend] AS [Is Weekend], [Is_Leap_Year] AS [Is Leap Year], [Is_England_Wales_Bank_Holiday] AS [Is England Wales Bank Holiday], [Is_Scotland_Bank_Holiday] AS [Is Scotland Bank Holiday]
FROM Gold.[Dim_Date];
GO
