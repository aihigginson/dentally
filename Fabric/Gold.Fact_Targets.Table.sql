/****** Object:  Table [Gold].[Fact_Targets]    Script Date: 06/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Targets]
GO
CREATE TABLE [Gold].[Fact_Targets] (
    [pk_target]          BIGINT IDENTITY NOT NULL,
    [Tenant_ID]          INT          NOT NULL,
    [bk_target_id]       BIGINT       NOT NULL,
    [fk_Practice_Site]   BIGINT       NOT NULL,
    [fk_Practitioner]    BIGINT       NOT NULL,
    [fk_Date]            BIGINT       NOT NULL,
    [Metric]             VARCHAR(100) NOT NULL,
    [Period_Type]        VARCHAR(20)  NOT NULL,
    [Period_Value]       VARCHAR(20)  NOT NULL,
    [Target_Value]       DECIMAL(18,4) NOT NULL,
    [Variance]           DECIMAL(10,4) NULL,
    [DW_Created_At]      DATETIME2(3) NOT NULL,
    [DW_Updated_At]      DATETIME2(3) NOT NULL
)
GO
