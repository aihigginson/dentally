/****** Object:  Table [Audit].[Ingest_Log] ******/
-- Live progress log for Ingest_Dentally (the Dentally API pull). The ingest runs INLINE in the
-- orchestrator's Spark session and only prints to the notebook's cell output, which isn't
-- queryable mid-run -- so a long pull is a go/no-go blind spot. Ingest_Dentally writes one row per
-- entity phase (START / WINDOW / DONE / SKIP) here via a direct warehouse connection (autocommit,
-- immediately visible -- no SQL-endpoint lag), so a running pull can be watched in SQL:
--   SELECT * FROM Audit.Ingest_Log WHERE Run_UUID = @run ORDER BY Logged_At DESC;
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Audit].[Ingest_Log]
GO
CREATE TABLE [Audit].[Ingest_Log](
    [Run_UUID]    [varchar](36)  NULL,   -- correlates to Orchestrate_Build's parent run
    [Tenant_ID]   [int]          NULL,
    [Entity]      [varchar](100) NULL,   -- endpoint / stage table
    [Phase]       [varchar](20)  NULL,   -- START | WINDOW | DONE | SKIP
    [Rows_Landed] [bigint]       NULL,
    [Detail]      [varchar](1000) NULL,  -- window span, error text, etc.
    [Logged_At]   [datetime2](3) NULL
)
GO
