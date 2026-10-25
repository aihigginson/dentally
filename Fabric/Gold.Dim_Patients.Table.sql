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
    -- V229: the patient lifecycle, and who their dentist actually is over time.
    -- fk_Patient_Status -> Gold.Dim_Patient_Status (reference data, no Tenant_ID, no RLS).
    [fk_Patient_Status]                  [int]           NULL,
    -- ==> OWNERSHIP IS ESTABLISHED BY EXAMS, NOT BY VISITS. <== One exam with an unfamiliar
    -- dentist plus three follow-up treatment appointments is NOT a change of dentist; those
    -- treatments are the consequence of that single exam. A spell therefore needs TWO
    -- CONSECUTIVE exams, and is dated from the FIRST of them -- so the history reads
    -- correctly even though the change can only be confirmed at the second.
    -- V233: the CURRENT allocation as surrogate keys. Dentist_Practitioner_ID and
    -- Hygienist_Practitioner_ID above are Dentally ids and cannot join Dim_Practitioners,
    -- so without these no patient-grain visual can follow a Practitioner or Role filter --
    -- which is how every report filters. Allocation, not attendance: see
    -- Last_Allocated_Dentist_Visit_Date for whether they have actually been seen.
    [fk_Current_Dentist]                 [bigint]        NULL,
    [fk_Current_Hygienist]               [bigint]        NULL,
    [fk_Prior_Dentist]                   [bigint]        NULL,   -- pk_Practitioner of the previous spell; NULL = never changed
    [fk_Date_Current_Dentist_Since]      [int]           NULL,
    [Current_Dentist_Since_Date]         [date]          NULL,
    [fk_Date_Last_Seen_Prior_Dentist]    [int]           NULL,
    [Last_Seen_Prior_Dentist_Date]       [date]          NULL,
    [Dentist_Spell_Count]                [int]           NULL,   -- qualifying spells, not appointments
    [Has_Settled_Dentist]                [bit]           NULL,   -- 0 = never two consecutive exams with one dentist
    [Dentist_Exam_Count]                 [int]           NULL,
    [Exams_With_Current_Dentist]         [int]           NULL,
    [Patient_Count]                      [int]           NOT NULL,
    [DW_Created_At]                      [datetime2](6)  NOT NULL,
    [DW_Updated_At]                      [datetime2](6)  NOT NULL
)
GO
