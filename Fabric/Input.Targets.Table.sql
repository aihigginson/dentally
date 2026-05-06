/****** Object:  Table [Input].[Targets]    Script Date: 06/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Input].[Targets]
GO
CREATE TABLE [Input].[Targets] (
    [pk_target]          INT IDENTITY NOT NULL,
    [Tenant_ID]          INT          NOT NULL,
    [Site_ID]            VARCHAR(50)  NULL,
    [Practitioner_ID]    INT          NULL,
    [Metric]             VARCHAR(100) NOT NULL,
    [Period_Type]        VARCHAR(20)  NOT NULL,
    [Period_Value]       VARCHAR(20)  NOT NULL,
    [Target_Value]       DECIMAL(18,4) NOT NULL,
    [DW_Created_At]      DATETIME2(3) NOT NULL,
    [DW_Updated_At]      DATETIME2(3) NOT NULL
)
GO
