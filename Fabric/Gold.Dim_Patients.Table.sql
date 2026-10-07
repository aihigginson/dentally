/****** Object:  Table [Gold].[Dim_Patients]    Script Date: 20/04/2026 10:15:06 ******/
-- Data-minimised patient dimension (V011, 2026-06-17). Special-category and
-- excess-identifier fields removed (NHS/NI/PPS numbers, Ethnicity, DOB/Age,
-- Gender, Medical Alert, full Address, Emergency Contact, Title/Middle name,
-- Family/Custom/Legacy, NHS exemption). Retained: identity-for-contact (names +
-- preferred name, phone, email), contactability flags (Recall_Method + the
-- contact-preference fields Use_Email / Use_SMS / Preferred_Phone, re-added V015),
-- and non-sensitive operational analytics (active, recall/appointment/exam dates,
-- acquisition, financial totals, site/practitioner). See DPIA.md sec 7.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Patients]
GO
CREATE TABLE [Gold].[Dim_Patients](
    [pk_Patient]                         [bigint]        NOT NULL,
    [Tenant_ID]                          [int]           NOT NULL,
    [Patient_ID]                         [int]           NOT NULL,
    [Account_ID]                         [int]           NULL,
    [First_Name]                         [varchar](100)  NULL,
    [Last_Name]                          [varchar](100)  NULL,
    [Preferred_Name]                     [varchar](100)  NULL,
    [Full_Name]                          [varchar](255)  NULL,
    [Date_Of_Birth]                      [date]          NULL,   -- V171: re-landed after V011; see DPIA 7.3
    [Age]                                [int]           NULL,   -- derived AS AT THE LOAD, so at most a day stale
    [Email_Address]                      [varchar](255)  NULL,
    [Home_Phone]                         [varchar](50)   NULL,
    [Mobile_Phone]                       [varchar](50)   NULL,
    [Is_Email_Missing]                   [bit]           NULL,
    [Is_Phone_Missing]                   [bit]           NULL,
    [Active]                             [bit]           NULL,
    [Payment_Plan_ID]                    [int]           NULL,
    [Standard_Payment_Plan]              [varchar](100)  NULL,
    [Site_ID]                            [varchar](50)   NULL,
    [Acquisition_Source_ID]              [varchar](50)   NULL,
    [fk_Acquisition_Source]              [bigint]        NULL,
    [Dentist_Practitioner_ID]            [int]           NULL,
    [Hygienist_Practitioner_ID]          [int]           NULL,
    [Dentist_Recall_Date]                [date]          NULL,
    [Dentist_Recall_Interval_Months]     [int]           NULL,
    [Hygienist_Recall_Date]              [date]          NULL,
    [Hygienist_Recall_Interval_Months]   [int]           NULL,
    [Recall_Method]                      [varchar](100)  NULL,
    [Use_Email]                          [bit]           NULL,
    [Use_SMS]                            [bit]           NULL,
    [Preferred_Phone]                    [varchar](50)   NULL,
    [Marketing_Consent]                  [varchar](255)  NULL,
    [First_Appointment_Date]             [date]          NULL,
    [Last_Appointment_Date]              [date]          NULL,
    [Next_Appointment_Date]              [date]          NULL,
    [First_Exam_Date]                    [date]          NULL,
    [Last_Exam_Date]                     [date]          NULL,
    [Next_Exam_Date]                     [date]          NULL,
    [Last_Scale_Polish_Date]             [date]          NULL,
    [Next_Scale_Polish_Date]             [date]          NULL,
    [Last_FTA_Date]                      [date]          NULL,
    [Last_Cancelled_Appointment_Date]    [date]          NULL,
    -- V216: last seen by ROLE, and by the patient's OWN dentist. Last_Exam_Date and
    -- Last_Scale_Polish_Date above are Dentally's, and they are procedures rather than
    -- people: a hygienist does most scale and polishes but not all of them, and an exam is
    -- not the only reason a patient sits in a dentist's chair. These three are by the
    -- clinician, which is what a plan review and the allocation checks need.
    [Last_Dentist_Visit_Date]            [date]          NULL,
    [Last_Hygienist_Visit_Date]          [date]          NULL,
    [Last_Allocated_Dentist_Visit_Date]  [date]          NULL,   -- NULL = never seen by them
    [Total_Paid]                         [decimal](18, 4) NULL,
    [Total_Invoiced]                     [decimal](18, 4) NULL,
    [Patient_Created_Date]               [date]          NULL,
    [Patient_Updated_Date]               [date]          NULL,
    [Lapsed_Type]                        [varchar](30)   NULL,
    [fk_Date_Lapsed]                     [int]           NULL,
    [Lapsed_Date]                        [date]          NULL,
    [Lapsed_Reason]                      [varchar](255)  NULL,
    [Patient_Count]                      [int]           NOT NULL,
    [DW_Created_At]                      [datetime2](6)  NOT NULL,
    [DW_Updated_At]                      [datetime2](6)  NOT NULL
)
GO
