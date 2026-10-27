/****** Object:  Table [Silver].[Recall_Reminders]    Script Date: 26/10/2026 ******/
--------------------------------------------------------------------
--  Table  :  Silver.Recall_Reminders
--  Author :  AIH
--  Date   :  26/10/2026
--
--  ONE ROW PER REMINDER ACTUALLY SENT, DECODED FROM THE reminders ARRAY.
--
--  ==> THE SCALAR REMINDER FIELDS FROM DENTALLY ARE NOT WHAT THEY SAY. <== Proven by GUID,
--  not inferred: first_reminder_id equals the NEWEST element's id on 267 of 267 staged
--  recalls that have any reminder, and the genuine first only on the 69 that have exactly
--  one. first_reminder_sent_at matches last_reminded_at to sub-second rounding on every row.
--  second_reminder_sent_at and second_reminder_id are never populated at all.
--
--  So "First Reminder Sent Date" showed the MOST RECENT chase for all 5,777 of the live
--  practice's recalls with two or more reminders, and V247's second-reminder fallback --
--  derived from last_reminded_at -- reproduced the same value, which is why the two columns
--  read identically on the Day Book screen.
--
--  The array is the only honest source. times_contacted equals its length EXACTLY on all
--  292 staged rows, every value 0 to 6, so the sequence below can be trusted. The
--  template_name even carries the position the practice gave it ("- OAB Dental recall 2").
--
--  Grain: Tenant x Recall x Reminder. bk_Reminder_ID is Dentally's own GUID for the
--  individual reminder, which makes it the natural key -- Reminder_Seq is DERIVED by date
--  and must never be treated as one, because a late-arriving earlier reminder would
--  renumber the rest.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('[Silver].[Recall_Reminders]', 'U') IS NULL
CREATE TABLE [Silver].[Recall_Reminders](
	[Tenant_ID]        [int]            NOT NULL,
	[bk_Recall_ID]     [VARCHAR](255)   NOT NULL,
	[bk_Reminder_ID]   [VARCHAR](255)   NOT NULL,  -- Dentally's GUID for this reminder
	[Reminder_Seq]     [smallint]       NULL,      -- 1 = the FIRST sent, ascending by Sent_At
	[Reminder_Type]    [VARCHAR](50)    NULL,      -- SMS | Email
	[Sent_At]          [datetime2](3)   NULL,
	[Template_Name]    [VARCHAR](255)   NULL,      -- e.g. '- OAB Dental recall 2'
	[DW_Created_At]    [datetime2](3)   NOT NULL,
	[DW_Updated_At]    [datetime2](3)   NOT NULL
)
GO
