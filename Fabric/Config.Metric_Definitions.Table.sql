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
    [Section]                 VARCHAR(50)    NOT NULL,
    [Format_Type]             VARCHAR(20)    NOT NULL,
    [Description]             VARCHAR(500)   NULL,   -- short, one-line (tooltip / card)
    [Long_Description]        VARCHAR(1000)  NULL,   -- plain-English definition (glossary / help panel)
    [Supports_Site]           BIT            NOT NULL,
    [Supports_Practitioner]   BIT            NOT NULL,
    [Is_Active]               BIT            NOT NULL,
    [Display_Order]           INT            NOT NULL,
    [Range_Type]              VARCHAR(10)    NOT NULL,   -- above | below | within
    [Target_Type]             VARCHAR(20)    NOT NULL,   -- cumulative | rate | point_in_time
    [Has_Target]              BIT            NULL,        -- 0 = no separate target (excluded from the targets template); NULL/1 = has a target
    [Target_Practitioner_Roles] VARCHAR(200) NULL         -- NULL = all supported practitioners; else CSV of roles the target applies to, e.g. 'Dentist'
)
GO
