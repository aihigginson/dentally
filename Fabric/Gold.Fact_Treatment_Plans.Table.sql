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
    [DW_Created_At]             [datetime2](6)   NOT NULL,
    [DW_Updated_At]             [datetime2](6)   NOT NULL
)
GO
