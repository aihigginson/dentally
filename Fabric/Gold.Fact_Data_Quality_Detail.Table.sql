/****** Object:  Table [Gold].[Fact_Data_Quality_Detail]    Script Date: 23/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Fact_Data_Quality_Detail
--  Author :  AIH
--  Notes  :  Grain   : one row per offending record per check. The named list behind every
--                      count on Gold.Aggregate_Data_Quality, so "471 overdue recalls" becomes
--                      471 patients a practice manager can work through on Monday morning.
--            Pattern : Aggregate -- full DELETE + INSERT each run, pk from ROW_NUMBER().
--
--            LONG FORMAT, DELIBERATELY. The checks span five different entities -- patients,
--            appointments, recalls, clinicians, treatments -- so there is no wide shape that
--            suits them all. Instead every row carries the same six presentation columns and
--            Detail_Label says what Detail_Date means for THAT check ('Last seen', 'Due',
--            'Registered'). One drillthrough page then serves all fourteen checks, and adding
--            a fifteenth needs no report change at all.
--
--            Tenant_Check_Key (Tenant_ID + '|' + Check_Code) is the join to the aggregate.
--            Check_Code alone would be many-to-many across tenants: it is unique per tenant,
--            not globally. RLS hides other tenants at runtime, but the semantic model resolves
--            relationships against the whole table, so the key has to carry the tenant.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Data_Quality_Detail]
GO
CREATE TABLE [Gold].[Fact_Data_Quality_Detail] (
    [pk_Data_Quality_Detail] [bigint]        NOT NULL,
    [Tenant_ID]              [int]           NOT NULL,
    [Tenant_Check_Key]       [varchar](80)   NOT NULL,   -- joins to Aggregate_Data_Quality
    [Check_Code]             [varchar](50)   NOT NULL,
    [Check_Category]         [varchar](30)   NOT NULL,
    [Check_Name]             [varchar](200)  NOT NULL,
    [Severity]               [varchar](10)   NOT NULL,
    [Severity_Sort]          [smallint]      NOT NULL,
    [fk_Patient]             [bigint]            NULL,   -- set where the row IS about a patient
    [Record_Type]            [varchar](20)   NOT NULL,   -- Patient|Appointment|Recall|Clinician|Treatment
    [Record_Name]            [varchar](200)      NULL,   -- the person or thing to act on
    [Record_Reference]       [varchar](100)      NULL,   -- the Dentally id, so it can be found
    [Detail_Date]            [date]              NULL,   -- the date that matters for this check
    [Detail_Label]           [varchar](50)       NULL,   -- what Detail_Date means
    [Detail_Note]            [varchar](300)      NULL,   -- contact, clinician, state -- per check
    -- When is this person next through the door? A list of 6,742 patients is not a worklist;
    -- the 338 of them due in the next seven days is, because the fix for most of these checks
    -- is to ask at the desk. NULL/'Not applicable' for clinician and treatment rows.
    [fk_Date_Next_Appointment]   [int]           NULL,   -- Gold.Dim_Date, days-since-1999 epoch
    [Next_Appointment_Date]      [date]          NULL,
    [Next_Appointment_Days]      [int]           NULL,   -- days from now; sort ascending
    [Next_Appointment_Band]      [varchar](20)   NOT NULL,
    [Next_Appointment_Band_Sort] [smallint]      NOT NULL,
    [DW_Created_At]          [datetime2](6)  NOT NULL,
    [DW_Updated_At]          [datetime2](6)  NOT NULL
)
GO
