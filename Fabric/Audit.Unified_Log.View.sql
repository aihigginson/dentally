/****** Object:  View [Audit].[Unified_Log] -- one timeline over the two run logs ******/
-- A single monitorable surface over BOTH existing logs, so a build/ingest run can be watched
-- live in one place -- procedures, ingest and the Orchestrate_Build notebook heartbeat interleaved
-- by time. No new writers: it UNIONs the tables the ETL framework already writes.
--
--   Source = PROCEDURE : Audit.Process_Execution_Log (each SP run via ETL_Run_Process)
--            INGEST     : Audit.Ingest_Log rows from the per-entity API->Stage pulls
--            NOTEBOOK   : Audit.Ingest_Log rows written by Orchestrate_Build's build_log() heartbeat
--
-- Monitor live:
--   SELECT Source, Name, Phase_Status, Detail, Rows_Affected, Logged_At
--   FROM   Audit.Unified_Log
--   WHERE  Logged_At > DATEADD(hour, -2, SYSUTCDATETIME())
--   ORDER  BY Logged_At DESC;
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [Audit].[Unified_Log]
GO
CREATE VIEW [Audit].[Unified_Log] AS
SELECT
      'PROCEDURE'                                    AS Source
    , p.Start_Time                                   AS Logged_At
    , CAST(COALESCE(p.Parent_Run_UUID, p.Run_UUID) AS varchar(36)) AS Run_UUID
    , CAST(NULL AS int)                              AS Tenant_ID
    , p.Process_Name                                 AS Name
    , p.Status                                       AS Phase_Status
    , CAST(ISNULL(p.Rows_Inserted,0) + ISNULL(p.Rows_Updated,0) + ISNULL(p.Rows_Deleted,0) AS bigint) AS Rows_Affected
    , p.Error_Message                                AS Detail
    , p.Start_Time                                   AS Start_Time
    , p.End_Time                                     AS End_Time
    , p.Duration_Seconds                             AS Duration_Seconds
FROM Audit.Process_Execution_Log p
UNION ALL
SELECT
      CASE WHEN i.Entity = 'Orchestrate_Build' THEN 'NOTEBOOK' ELSE 'INGEST' END AS Source
    , i.Logged_At                                    AS Logged_At
    , i.Run_UUID                                     AS Run_UUID
    , i.Tenant_ID                                    AS Tenant_ID
    , i.Entity                                       AS Name
    , i.Phase                                        AS Phase_Status
    , i.Rows_Landed                                  AS Rows_Affected
    , i.Detail                                       AS Detail
    , i.Logged_At                                    AS Start_Time
    , CAST(NULL AS datetime2(6))                     AS End_Time
    , CAST(NULL AS float)                            AS Duration_Seconds
FROM Audit.Ingest_Log i;
GO
