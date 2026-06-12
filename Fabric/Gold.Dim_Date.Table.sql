/****** Object:  Table [Gold].[Dim_Date]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Date]
GO
CREATE TABLE [Gold].[Dim_Date](
	[pk_Date] [int] NOT NULL,
	[Full_Date] [date] NOT NULL,
	[Day_Name] [varchar](10) NOT NULL,
	[Day_Of_Week] [smallint] NOT NULL,
	[Day_Of_Month] [smallint] NOT NULL,
	[Day_Of_Year] [smallint] NOT NULL,
	[Week_Of_Year] [smallint] NOT NULL,
	[Week_Of_Month] [smallint] NOT NULL,
	[Calendar_Year_Week] [int] NOT NULL,
	[Week_Commencing_Date] [date] NOT NULL,
	[Week_Ending_Date] [date] NOT NULL,
	[Month_Number] [smallint] NOT NULL,
	[Month_Name] [varchar](10) NOT NULL,
	[Month_Name_Short] [varchar](3) NOT NULL,
	[Month_Year] [varchar](10) NOT NULL,
	[Month_Commencing_Date] [date] NOT NULL,
	[Month_Ending_Date] [date] NOT NULL,
	[Calendar_Quarter] [smallint] NOT NULL,
	[Calendar_Quarter_Name] [varchar](2) NOT NULL,
	[Calendar_Year] [smallint] NOT NULL,
	[Calendar_Year_Month] [int] NOT NULL,
	[Calendar_Year_Quarter] [varchar](7) NOT NULL,
	[Relative_Day] [int] NOT NULL,
	[Relative_Week] [int] NOT NULL,
	[Relative_Month] [int] NOT NULL,
	[Relative_Quarter] [int] NOT NULL,
	[Relative_Year] [int] NOT NULL,
	[Financial_Year] [smallint] NOT NULL,
	[Financial_Year_Name] [char](10) NOT NULL,
	[Financial_Quarter] [smallint] NOT NULL,
	[Financial_Quarter_Name] [varchar](11) NOT NULL,
	[Financial_Month] [smallint] NOT NULL,
	[Financial_Month_Name] [varchar](20) NOT NULL,
	[Financial_Week] [smallint] NOT NULL,
	[Financial_Day_Of_Year] [smallint] NOT NULL,
	[Relative_Financial_Day] [int] NOT NULL,
	[Relative_Financial_Week] [int] NOT NULL,
	[Relative_Financial_Month] [int] NOT NULL,
	[Relative_Financial_Quarter] [int] NOT NULL,
	[Relative_Financial_Year] [int] NOT NULL,
	[Is_Weekend] [bit] NOT NULL,
	[Is_Leap_Year] [bit] NOT NULL,
	[Is_England_Wales_Bank_Holiday] [bit] NOT NULL,
	[Is_Scotland_Bank_Holiday] [bit] NOT NULL,
	[Is_Working_Day_England] [bit] NOT NULL
)
GO
