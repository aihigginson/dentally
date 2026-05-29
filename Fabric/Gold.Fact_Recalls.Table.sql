/****** Object:  Table [Gold].[Fact_Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Recalls]
GO
CREATE TABLE [Gold].[Fact_Recalls](
	[pk_Recall]              [bigint] IDENTITY NOT NULL,
	[Tenant_ID]              [int]           NOT NULL,
	[bk_Recall_ID]           [VARCHAR](50)   NOT NULL,
	[fk_Patient]             [bigint]        NULL,
	[fk_Date_Due]            [bigint]        NULL,
	[fk_Date_Run]            [bigint]        NULL,
	[fk_Date_First_Reminder] [bigint]        NULL,
	[fk_Date_Second_Reminder][bigint]        NULL,
	[fk_Date_Last_Reminded]  [bigint]        NULL,
	[Appointment_ID]         [VARCHAR](50)   NULL,
	[Recall_Type]            [VARCHAR](100)  NULL,
	[Recall_Method]          [VARCHAR](100)  NULL,
	[Status]                 [VARCHAR](100)  NULL,
	[Workflow_Status]        [VARCHAR](100)  NULL,
	[Workflow_Stage_ID]      [VARCHAR](50)   NULL,
	[First_Reminder_Type]    [VARCHAR](100)  NULL,
	[Second_Reminder_Type]   [VARCHAR](100)  NULL,
	[Latest_Reminder_Type]   [VARCHAR](100)  NULL,
	[Times_Contacted]        [int]           NULL,
	[Due_Date]               [date]          NULL,
	[Run_Date]               [date]          NULL,
	[Days_Overdue]           [int]           NULL,
	-- Pre-computed flags: replace heavy DAX set operations in Retention Outlook
	[Is_In_Scope]            [bit]           NULL,  -- first reminder sent OR due within [-24m, +1m] of ETL run
	[Is_Reminder_Sent]       [bit]           NULL,  -- First_Reminder_Sent_At IS NOT NULL
	[Is_Booked_Via_Recall]   [bit]           NULL,  -- Appointment_ID is set on the recall record
	[Is_Booked]              [bit]           NULL,  -- patient has a future non-cancelled appointment
	[Overdue_Band]           [varchar](20)   NULL,  -- 'Upcoming'/'01-30 Days'/'31-90 Days'/'91-180 Days'/'181+ Days'/'Booked'
	[Recall_Status]          [varchar](20)   NULL,  -- 'Booked'/'2nd Reminder'/'1st Reminder'/'Overdue'/'Not Yet Due'
	-- Next appointment enrichment (patient's soonest upcoming non-cancelled appointment)
	[fk_Date_Appt_Booked]    [bigint]        NULL,  -- date key for when next appointment was booked (Pending_At)
	[Appt_State]             [varchar](50)   NULL,  -- State of next appointment
	[Appt_Booked_Via_API]    [bit]           NULL,  -- was next appointment booked via API
	[Appt_Start_Time]        [datetime2](3)  NULL,  -- next appointment start time
	[Days_Recall_To_Booking] [int]           NULL   -- days from first reminder sent to next appointment booking date
	[DW_Created_At]          [datetime2](6)  NOT NULL,
	[DW_Updated_At]          [datetime2](6)  NOT NULL
)
GO


