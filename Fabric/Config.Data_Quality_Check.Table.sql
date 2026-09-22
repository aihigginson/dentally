/****** Object:  Table [Config].[Data_Quality_Check]    Script Date: 22/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Config.Data_Quality_Check
--  Author :  AIH
--  Notes  :  The CATALOGUE of data-quality checks -- one row per check, owner-curated.
--            Wording lives here, not in the load proc, so a check can be reworded,
--            re-graded or retired as a data change rather than a code change.
--
--            Gold.usp_Load_Aggregate_Data_Quality joins to this and denormalises the
--            text onto every row, so the Power BI side is ONE flat table with no
--            relationship to wire up.
--
--            Adding a check needs BOTH: a row here AND a counting branch in the proc,
--            matched on Check_Code. A row with no branch reports 0 for ever, which
--            reads as "clean" -- the worst possible failure for this table.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Config].[Data_Quality_Check]
GO
CREATE TABLE [Config].[Data_Quality_Check] (
    [Check_Code]      VARCHAR(50)   NOT NULL,   -- joins to the proc's counting branch
    [Check_Category]  VARCHAR(30)   NOT NULL,   -- Patients | Diary | Recalls | People | Treatments
    [Check_Name]      VARCHAR(200)  NOT NULL,   -- the one-line finding, in the practice's language
    [Severity]        VARCHAR(10)   NOT NULL,   -- High | Medium | Low
    [Severity_Sort]   SMALLINT      NOT NULL,   -- 1 High, 2 Medium, 3 Low -- for report sorting (Fabric has no TINYINT)
    [Why_It_Matters]  VARCHAR(500)  NULL,
    [What_To_Do]      VARCHAR(500)  NULL,
    [Population_Key]  VARCHAR(30)   NOT NULL,   -- which denominator Pct_Affected is out of
    [Is_Active]       BIT           NOT NULL,
    [Display_Order]   INT           NOT NULL
)
GO
