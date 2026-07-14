/****** Object:  Table [Gold].[Fact_Recall_Gap] ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Recall_Gap]
GO
-- One row per (active patient x discipline) whose PATIENT recall date falls in the next 4 weeks --
-- the Retention Outlook worklist. Cohort tags each: Booked (matching appt already booked),
-- Gap - Recall Active (not booked but a live Unbooked recall record is chasing them), or
-- Gap - No Recall (not booked and nothing actively contacting them -- the falling-through list).
CREATE TABLE [Gold].[Fact_Recall_Gap](
	[pk_Recall_Gap]            [bigint]        NOT NULL,
	[Tenant_ID]                [int]           NOT NULL,
	[fk_Patient]               [bigint]        NULL,
	[fk_Practice_Site]         [bigint]        NULL,
	[fk_Practitioner]          [bigint]        NULL,
	[Discipline]               [varchar](20)   NULL,
	[Recall_Date]              [date]          NULL,
	[Days_Until_Due]           [int]           NULL,
	[Cohort]                   [varchar](30)   NULL,
	[Has_Appointment]          [bit]           NULL,
	[Has_Live_Recall]          [bit]           NULL,
	[Next_Relevant_Appt_Date]  [date]          NULL,
	[DW_Created_At]            [datetime2](6)  NOT NULL,
	[DW_Updated_At]            [datetime2](6)  NOT NULL
)
GO
