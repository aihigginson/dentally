/****** Object:  Table [Config].[Metric_Definitions]    Script Date: 06/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Config].[Metric_Definitions]
GO
CREATE TABLE [Config].[Metric_Definitions] (
    [Metric_Key]              VARCHAR(100) NOT NULL,
    [Display_Name]            VARCHAR(200) NOT NULL,
    [Section]                 VARCHAR(50)  NOT NULL,
    [Format_Type]             VARCHAR(20)  NOT NULL,
    [Description]             VARCHAR(500) NULL,
    [Supports_Site]           BIT          NOT NULL,
    [Supports_Practitioner]   BIT          NOT NULL,
    [Is_Active]               BIT          NOT NULL,
    [Display_Order]           INT          NOT NULL
)
GO
