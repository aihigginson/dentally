/****** Object:  Table [Config].[Metric_Period_Types]    Script Date: 06/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Config].[Metric_Period_Types]
GO
CREATE TABLE [Config].[Metric_Period_Types] (
    [Metric_Key]    VARCHAR(100) NOT NULL,
    [Period_Type]   VARCHAR(20)  NOT NULL,
    [Is_Default]    BIT          NOT NULL
)
GO
