/****** Object:  Table [Config].[Metric_Definitions]    Script Date: 06/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Config].[Metric_Definitions]
GO
CREATE TABLE [Config].[Metric_Definitions] (
    [Metric_Key]              VARCHAR(100)   NOT NULL,
    [Display_Name]            VARCHAR(200)   NOT NULL,
    [Card_Label]              VARCHAR(60)    NULL,   -- short label for KPI cards (falls back to Display_Name)
    [Section]                 VARCHAR(50)    NOT NULL,
    [Format_Type]             VARCHAR(20)    NOT NULL,
    [Description]             VARCHAR(500)   NULL,   -- short, one-line (tooltip / card)
    [Long_Description]        VARCHAR(1000)  NULL,   -- plain-English definition (glossary / help panel)
    [Sample_Value] [VARCHAR](50) NULL,
    [Supports_Site]           BIT            NOT NULL,
    [Supports_Practitioner]   BIT            NOT NULL,
    [Is_Active]               BIT            NOT NULL,
    [Display_Order]           INT            NOT NULL,
    [Range_Type]              VARCHAR(10)    NOT NULL,   -- above | below | within
    [Target_Type]             VARCHAR(20)    NOT NULL,   -- cumulative | rate | point_in_time
    [Has_Target]              BIT            NULL,        -- 0 = no separate target (excluded from the targets template); NULL/1 = has a target
    [Target_Practitioner_Roles] VARCHAR(200) NULL,
    -- ==> ADDED BY V092 AS AN ALTER AND NEVER WRITTEN BACK HERE. <== Discovered on 09/10/2026
    -- by deploying this file: it DROPs and recreates, so the recreate silently removed a column
    -- the warehouse had and the re-seed then failed on 'Invalid column name FTE_Scaled'. Any
    -- ALTER-added column missing from here is a trap armed for whoever next deploys this file.
    [FTE_Scaled]              BIT            NULL,   -- target scales with the practitioner's FTE
        -- NULL = all supported practitioners; else CSV of roles the target applies to, e.g. 'Dentist'
    -- ==> THE METRIC'S WEIGHT WITHIN ITS HOME-PAGE AREA, OUT OF 100. <== The area header is a
    -- WEIGHTED average of its metrics' RAG bands, and these are the weights. Definitive HERE
    -- rather than in the model so they are visible, auditable, and available to anything else
    -- that wants them -- alerting was the example. PBI_Dentally.csx receives them by
    -- generation; the copy in the model is derived and must never be edited by hand.
    --
    -- NULL = not scored: informational tiles, and every metric not shown on the Home page.
    -- Each area sums to 100 on its own, so the five areas stay comparable with each other.
    [Area_Weight]             SMALLINT       NULL   -- Fabric has no TINYINT
)
GO
