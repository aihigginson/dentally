/****** Object:  Table [Input].[Targets]    Script Date: 06/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('[Input].[Targets]', 'U') IS NULL
CREATE TABLE [Input].[Targets] (
    [pk_target]          BIGINT IDENTITY NOT NULL,
    [Tenant_ID]          INT           NOT NULL,
    [Site_ID]            VARCHAR(50)   NULL,
    [Practitioner_ID]    INT           NULL,
    [Metric]             VARCHAR(100)  NOT NULL,
    [Period_Type]        VARCHAR(20)   NOT NULL,
    [Period_Value]       VARCHAR(20)   NOT NULL,
    [Target_Value]       DECIMAL(18,4) NOT NULL,
    [Variance]           DECIMAL(10,4) NULL,
    [DW_Created_At]      DATETIME2(3)  NOT NULL,
    [DW_Updated_At]      DATETIME2(3)  NOT NULL
)
GO

-- Add Variance to existing tables that predate this column
IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Targets' AND COLUMN_NAME = 'Variance'
)
    ALTER TABLE [Input].[Targets] ADD [Variance] DECIMAL(10,4) NULL
GO
