/****** Object:  Table [Gold].[Fact_Practitioner_Diaries]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Practitioner_Diaries]
GO
CREATE TABLE [Gold].[Fact_Practitioner_Diaries](
	[pk_Practitioner_Diary] [bigint] IDENTITY NOT NULL,
	[Tenant_ID] [int] NOT NULL,
	[bk_Practitioner_Diary_ID] [VARCHAR](50) NOT NULL,
	[fk_Practitioner] [bigint] NULL,
	[fk_Date_Day] [bigint] NULL,
	[Day_Date] [date] NULL,
	[Start_Time] [time](0) NULL,
	[End_Time] [time](0) NULL,
	[Unavailable] [bit] NULL,
	[Session_Duration_Mins] [int] NULL,
	[Total_Break_Mins] [int] NULL,
	[Available_Clinical_Mins] [int] NULL,
	[Break_Count] [int] NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO


