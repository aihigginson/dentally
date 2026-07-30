/****** Object:  Table [Bronze].[Recalls]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
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
    [DW_Loaded_At]            [datetime2](3)  NULL
)
GO
