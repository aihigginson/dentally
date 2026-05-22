/****** Object:  Table [Gold].[Fact_Daily_Targets]    Script Date: 17/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Daily_Targets]
GO
CREATE TABLE [Gold].[Fact_Daily_Targets] (
    [pk_Daily_Target]    BIGINT IDENTITY NOT NULL,
    [Tenant_ID]          INT           NOT NULL,
    [Site_ID]            VARCHAR(50)   NULL,
    [Practitioner_ID]    INT           NULL,
    [fk_Date]            INT           NOT NULL,
    [Metric]             VARCHAR(100)  NOT NULL,
    [Daily_Target_Value] DECIMAL(18,6) NOT NULL,
    [Variance]           DECIMAL(10,4) NULL,
    [DW_Created_At]      DATETIME2(3)  NOT NULL
)
GO
