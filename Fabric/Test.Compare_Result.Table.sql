/****** Object:  Table [Test].[Compare_Result] ******/
-- Persisted output of Test.usp_Compare. One unified row shape for BOTH check
-- types so it is easy to query, dump and trend:
--   REGRESSION : Value_A = Current, Value_B = Baseline, Expected_Difference = 0.
--   RECONCILE  : Value_A / Value_B = the two metrics, Expected_Difference = the
--                comparison's configured offset.
-- In both cases  Actual_Difference = Value_A - Value_B  and
--                Deviation         = Actual_Difference - Expected_Difference.
-- Each usp_Compare call appends a new Run_Id, so the table keeps a history of
-- comparison runs (filter to the latest Run_Id for the most recent result).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Test].[Compare_Result]
GO
CREATE TABLE [Test].[Compare_Result](
    [Run_Id]              [uniqueidentifier] NOT NULL,   -- one per usp_Compare call
    [Compare_Run_At]      [datetime2](3)     NOT NULL,
    [Run_Tag]             [varchar](200)     NULL,        -- carried from Capture_Current
    [Check_Type]          [varchar](20)      NOT NULL,    -- REGRESSION | RECONCILE
    [Item_Name]           [varchar](200)     NOT NULL,    -- metric or comparison name
    [Metric_A]            [varchar](200)     NULL,
    [Metric_B]            [varchar](200)     NULL,
    [Value_A]             [decimal](38,4)    NULL,
    [Value_B]             [decimal](38,4)    NULL,
    [Expected_Difference] [decimal](38,4)    NULL,
    [Actual_Difference]   [decimal](38,4)    NULL,
    [Deviation]           [decimal](38,4)    NULL,
    [Status]              [varchar](40)      NOT NULL,
    [Detail]              [varchar](4000)    NULL
)
GO
