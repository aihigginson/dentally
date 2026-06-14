/****** Object:  Table [Test].[Comparison_Definition] ******/
-- Cross-metric reconciliation rules (e.g. Bronze vs Gold). A comparison PASSES
-- when  value(Metric_A) - value(Metric_B) = Expected_Difference.
-- Sign convention: Actual = value(A) - value(B). So -1 means "A has one fewer
-- than B" (e.g. Silver one short of Gold's dimension sentinel row).
-- Nearly all Expected_Difference are 0; the column exists for constant offsets.
-- NOTE: regression (Current vs Baseline per metric) is implicit and needs NO
-- rows here -- this table is ONLY for same-run cross-layer reconciliation.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Test].[Comparison_Definition]
GO
CREATE TABLE [Test].[Comparison_Definition](
    [Comparison_Name]     [varchar](200)  NOT NULL,
    [Metric_A]            [varchar](200)  NOT NULL,
    [Metric_B]            [varchar](200)  NOT NULL,
    [Expected_Difference] [decimal](38,4) NOT NULL,
    [Description]         [varchar](1000) NULL,
    [Is_Active]          [bit]            NOT NULL
)
GO
