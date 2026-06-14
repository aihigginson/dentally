/****** Object:  Table [Test].[Capture_Baseline] ******/
-- The "last known-good" snapshot. Identical structure to Test.Capture_Current.
-- Populated only by Test.usp_Promote (which copies Current -> Baseline once the
-- variances have been reviewed and accepted). This is the table that gets
-- dumped to a flat file for inclusion in a release.
--
-- DATA-BEARING: created only if absent (guarded), NOT DROP/CREATE. A redeploy
-- must NOT wipe the baseline -- otherwise every run would re-capture against an
-- empty baseline, report all metrics as "NEW", and never catch a regression
-- (the same data-preservation lesson the Migrations regime exists for). To
-- rebuild the structure deliberately, drop it by hand first, then redeploy.
IF NOT EXISTS (
    SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'Test' AND t.name = 'Capture_Baseline')
CREATE TABLE [Test].[Capture_Baseline](
    [Metric_Name]   [varchar](200)  NOT NULL,
    [Value]         [decimal](38,4) NULL,
    [Captured_At]   [datetime2](3)  NOT NULL,
    [Run_Tag]       [varchar](200)  NULL,        -- release / git sha label
    [Error_Message] [varchar](4000) NULL         -- non-null = capture SQL failed
)
GO
