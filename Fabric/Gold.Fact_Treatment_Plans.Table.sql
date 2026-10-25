/****** Object:  Table [Gold].[Fact_Treatment_Plans]    Script Date: 21/06/2026 ******/
-- Plan-grain fact (1 row per treatment plan). Models the treatment plan with its OWN
-- foreign keys (practitioner, site, dates) so plan-level measures (Open Courses, Average
-- Plan Value, Treatment Acceptance Rate) can be sliced by the PLAN's practitioner / site /
-- date directly -- instead of the old hack of routing through Gold.Fact_Treatment_Plan_Items
-- (line grain) via DISTINCT(fk Treatment Plan), which mis-attributed / dropped plans based on
-- their ITEMS' practitioner/site/date. Gold.Dim_Treatment_Plans remains the shared dimension
-- (both this fact and Fact_Treatment_Plan_Items relate to it via fk_Treatment_Plan).
--
-- MODELLING NOTE: in the PBI model, make the Practitioner / Patient / Treatment Plan
-- relationships ACTIVE so those slicers work natively. Leave the date relationships
-- (fk_Date_*) INACTIVE -- "Open Courses" is a current-state count that must NOT respond to a
-- page/embed date slicer; surface specific date views via USERELATIONSHIP only where wanted.
-- fk_Practice_Site is ALWAYS -1: the Dentally treatment-plan object carries no site, so plans
-- cannot be sliced by site (the column is kept only for star-schema/RLS consistency).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Treatment_Plans]
GO
CREATE TABLE [Gold].[Fact_Treatment_Plans](
    [pk_Treatment_Plan_Fact]    [bigint] IDENTITY NOT NULL,
    [Tenant_ID]                 [int]            NOT NULL,
    [bk_Treatment_Plan_ID]      [int]            NOT NULL,
    [fk_Treatment_Plan]         [bigint]         NULL,
    [fk_Patient]                [bigint]         NULL,
    [fk_Practitioner]           [bigint]         NULL,
    [fk_Practice_Site]          [bigint]         NULL,
    [fk_Date_Created]           [bigint]         NULL,
    [fk_Date_Start]             [bigint]         NULL,
    [fk_Date_Completed]         [bigint]         NULL,
    [Completed]                 [bit]            NULL,
    [Start_Date]                [date]           NULL,
    [Treatment_Plan_Count]      [int]            NOT NULL,
    [NHS_UDA_Value]             [decimal](18, 4) NULL,
    [NHS_Completed_UDA_Value]   [decimal](18, 4) NULL,
    [Private_Treatment_Value]   [decimal](18, 4) NULL,
    -- Item roll-up: value split (private-only, NHS_Charge=0) + course lifecycle state.
    [Private_Treatment_Value_Completed]   [decimal](18, 4) NULL,
    [Private_Treatment_Value_Outstanding] [decimal](18, 4) NULL,
    [Last_Activity_Date]        [date]           NULL,
    [Has_Completed_Item]        [bit]            NULL,
    [Has_Open_Item]             [bit]            NULL,
    [Has_Future_Appointment]    [bit]            NULL,
    [Course_Status]             [varchar](40)    NULL,
    -- V229. Front-loading: how much of a patient's work this clinician put in the FIRST
    -- plan they ever wrote for them. Measured as a share it is bounded 0-1, so one large
    -- case cannot move a clinician several places the way a ratio of two means does.
    -- ==> FIRST MET IS PER PATIENT AND PER CLINICIAN, NOT THE PATIENT'S FIRST EVER VISIT.
    -- <== Front-loading happens at the start of a RELATIONSHIP; a patient who transfers to
    -- a new dentist after ten years gets a first-meeting plan from them too.
    [Is_First_Visit_Plan]       [bit]            NULL,
    [First_Met_Date]            [date]           NULL,   -- this clinician first saw this patient
    -- ==> THE DENOMINATOR FOR FRONT-LOADING. <== A share of everything EVER planned is
    -- mostly a measure of how long the relationship has run: at the live practice it put
    -- the former owner last (36.4%) because his patients averaged 59 months with him, and
    -- a clinician with 16-month relationships above him on 53%. Fixing the window to each
    -- patient's first twelve months removes that and leaves the real signal -- one
    -- associate at 84.8% against a pack at 64-70%.
    [Is_First_Year_Plan]        [bit]            NULL,
    -- Banded, not a Is_Large flag. One threshold cannot serve an implantologist whose
    -- ordinary case is 4,654 pounds and a routine course of 50, across practices with
    -- different price lists -- and a stored judgement cannot be revised without restating
    -- history. The band is a fact; "large" is a comparison, and comparisons live in the
    -- metric against the Custom_Role median.
    [Plan_Value_Band]           [varchar](20)    NULL,
    [Plan_Value_Band_Sort]      [int]            NULL,   -- PBI drops a sort on a non-projected column
    -- V231. Who paid. "No private value" meant four different things and read as
    -- "nothing happened"; see Gold.Dim_Plan_Payer. Tenantless reference data, no RLS.
    [fk_Plan_Payer]             [int]            NULL,
    [DW_Created_At]             [datetime2](6)   NOT NULL,
    [DW_Updated_At]             [datetime2](6)   NOT NULL
)
GO
