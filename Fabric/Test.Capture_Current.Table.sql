/****** Object:  Table [Test].[Capture_Current] ******/
-- Results of the latest capture run. Truncated and repopulated every time
-- Test.usp_Run_Captures runs. Identical structure to Test.Capture_Baseline so
-- Promote is a straight copy and Compare is a straight join.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Test].[Capture_Current]
GO
CREATE TABLE [Test].[Capture_Current](
    [Metric_Name]   [varchar](200)  NOT NULL,
    [Value]         [decimal](38,4) NULL,
    [Captured_At]   [datetime2](3)  NOT NULL,
    [Run_Tag]       [varchar](200)  NULL,
    [Error_Message] [varchar](4000) NULL
)
GO
