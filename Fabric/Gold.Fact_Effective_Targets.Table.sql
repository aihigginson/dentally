/****** Object:  Table [Gold].[Fact_Effective_Targets]    Script Date: 27/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Effective_Targets]
GO
CREATE TABLE [Gold].[Fact_Effective_Targets] (
    [pk_Effective_Target]   BIGINT IDENTITY NOT NULL,
    [Tenant_ID]             INT           NOT NULL,
    [fk_Practice_Site]      BIGINT        NOT NULL,
    [Metric]                VARCHAR(100)  NOT NULL,
    [Period_Type]           VARCHAR(20)   NOT NULL,
    [Period_Value]          VARCHAR(20)   NOT NULL,
    [Effective_Target]      DECIMAL(18,4) NOT NULL,
    [Effective_Variance]    DECIMAL(10,4) NULL
)
GO
