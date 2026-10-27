/****** Object:  Table [Bronze].[Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ==> NEVER PUT THIS FILE IN A RELEASE MANIFEST. <== It opens with DROP TABLE, and unlike
-- every other Bronze table this one CANNOT be rebuilt from Stage:
--   * Stage.Recalls is the latest ingest batch only -- 292 rows against 45,241 here.
--   * The loader's dedupe keeps one cycle per patient per type, so history never returns.
--   * The DEMO TENANTS ARE SEEDED STRAIGHT INTO BRONZE and never appear in Stage at all,
--     so dropping this destroys tenants 11 and 12 outright.
-- Deployed to DEV on 26/10/2026 while adding Reminders: 45,241 rows gone in a second, and
-- recoverable only because Silver.Recalls mirrors it 1:1 and was not dropped.
-- To add a column, ALTER TABLE ... ADD it in the manifest. This file states the SHAPE for
-- Check_Schema_Drift; it is not a deployment step.
DROP TABLE IF EXISTS [Bronze].[Recalls]
GO
CREATE TABLE [Bronze].[Recalls](
    [ID]                      [VARCHAR](255)  NULL,
    [Tenant_ID]               [int]           NULL,
    [Patient_ID]              [decimal](18,4) NULL,
    [Appointment_ID]          [VARCHAR](255)  NULL,
    [Due_Date]                [VARCHAR](255)  NULL,
    [Recall_Type]             [VARCHAR](255)  NULL,
    [Recall_Method]           [VARCHAR](255)  NULL,
    [Status]                  [VARCHAR](255)  NULL,
    [Prebooked]               [VARCHAR](10)   NULL,
    [First_Reminder_Sent_At]  [VARCHAR](255)  NULL,
    [First_Reminder_Type]     [VARCHAR](255)  NULL,
    [Second_Reminder_Sent_At] [VARCHAR](255)  NULL,
    [Second_Reminder_Type]    [VARCHAR](255)  NULL,
    [Last_Reminded_At]        [VARCHAR](255)  NULL,
    [Latest_Reminder_Type]    [VARCHAR](255)  NULL,
    [Times_Contacted]         [decimal](18,4) NULL,
    [Run_Date]                [VARCHAR](255)  NULL,
    [Workflow_Status]         [VARCHAR](255)  NULL,
    [Workflow_Stage_ID]       [VARCHAR](255)  NULL,
    [First_Reminder_ID]       [VARCHAR](255)  NULL,
    [Second_Reminder_ID]      [VARCHAR](255)  NULL,
    [Updated_At]              [VARCHAR](255)  NULL,
    -- ==> THE FULL REMINDER HISTORY, NEWEST FIRST. <== The scalar
    -- first_/second_reminder_* columns above are NOT what they say: Dentally
    -- sets first_reminder_id to the NEWEST reminder's GUID (267 of 267 staged
    -- recalls with any reminder) and never populates the second at all. This
    -- array is the only honest source, and Silver.Recall_Reminders decodes it.
    [Reminders]               [VARCHAR](8000) NULL,
    [DW_Loaded_At]            [datetime2](3)  NULL
)
GO
