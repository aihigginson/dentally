--------------------------------------------------------------------
--  View   :  Gold.vw_Fact_Treatment_Plans
--  Author :  AIH
--  Purpose:  Presentation source for the plan-grain treatment-plan fact. 1-1 passthrough
--            so Meta.usp_Create_Gold_Views wraps it into PBI.[_Treatment Plans] (stable name)
--            and skips the table's own PBI view. Gives the model a plan-grain fact with its
--            OWN fk_Practitioner / fk_Practice_Site / fk_Date_* so plan measures (Open Courses,
--            Average Plan Value, Treatment Acceptance Rate) stop routing through the line-grain
--            Fact_Treatment_Plan_Items.
--  History:
--    *01     21/06/2026  AIH Initial release.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP VIEW IF EXISTS [Gold].[vw_Fact_Treatment_Plans]
GO
CREATE VIEW [Gold].[vw_Fact_Treatment_Plans]
AS
SELECT
    f.pk_Treatment_Plan_Fact,
    f.Tenant_ID,
    f.bk_Treatment_Plan_ID,
    f.fk_Treatment_Plan,
    f.fk_Patient,
    f.fk_Practitioner,
    f.fk_Practice_Site,
    f.fk_Date_Created,
    f.fk_Date_Start,
    f.fk_Date_Completed,
    f.Completed,
    f.Start_Date,
    f.Treatment_Plan_Count,
    f.NHS_UDA_Value,
    f.NHS_Completed_UDA_Value,
    f.Private_Treatment_Value,
    f.DW_Created_At,
    f.DW_Updated_At
FROM Gold.Fact_Treatment_Plans f
GO
