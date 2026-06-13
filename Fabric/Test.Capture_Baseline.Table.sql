/****** Object:  Table [Test].[Capture_Baseline] ******/
-- The "last known-good" snapshot. Identical structure to Test.Capture_Current.
-- Populated only by Test.usp_Promote (which copies Current -> Baseline once the
-- variances have been reviewed and accepted). This is the table that gets
-- dumped to a flat file for inclusion in a release.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Test].[Capture_Baseline]
GO
CREATE TABLE [Test].[Capture_Baseline](
    [Metric_Name]   [varchar](200)  NOT NULL,
    [Value]         [decimal](38,4) NULL,
    [Captured_At]   [datetime2](3)  NOT NULL,
    [Run_Tag]       [varchar](200)  NULL,        -- release / git sha label
    [Error_Message] [varchar](4000) NULL         -- non-null = capture SQL failed
)
GO
