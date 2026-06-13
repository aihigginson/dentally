/****** Object:  Table [Test].[Metric_Definition] ******/
-- Catalogue of regression metrics. Each row holds a piece of dynamic SQL that
-- MUST return a single scalar number (a row count or a control total). The
-- runner (Test.usp_Run_Captures) executes every active row and writes the
-- scalar to Test.Capture_Current.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Test].[Metric_Definition]
GO
CREATE TABLE [Test].[Metric_Definition](
    [Metric_Name]  [varchar](200)  NOT NULL,   -- natural key, e.g. BRONZE_PATIENTS_T11
    [Metric_Group] [varchar](100)  NULL,        -- e.g. Row Count, Control Total
    [Layer]        [varchar](20)   NULL,        -- Bronze | Silver | Gold (informational)
    [Value_Type]   [varchar](20)   NULL,        -- count | currency
    [SQL_Text]     [varchar](4000) NOT NULL,    -- returns ONE scalar value
    [Description]  [varchar](1000) NULL,
    [Is_Active]    [bit]           NOT NULL
)
GO
