---
name: prefer-temp-tables-over-ctes
description: The owner does not write CTEs - use temp tables and straight SQL in Fabric warehouse procedures, for both style and cost.
metadata:
  type: feedback
---

Write **temp tables and straight SQL**, not CTEs, in warehouse procedures. Every CTE in this
codebase was written by me, not the owner, who said so plainly on 2026-09-29: *"I hate CTEs and
if any exist in the solution you have written them."*

**Why:** in Fabric it is a performance decision as much as a style one. A CTE is not materialised,
so a CTE referenced N times re-evaluates its source N times, and when the source is a view with
computed columns the optimiser has no statistics to plan with. `Gold.usp_Load_Dim_Date_Grouping`
referenced one CTE over `Gold.vw_Dim_Date` five times and self-joined it, pairing 14,976 dates
against 14,976 dates — 224 million combinations — to keep 2,553 rows, at **1,047 CPU-seconds a
night, about 43% of prod's entire warehouse compute**. A temp table evaluates once and carries
statistics.

**How to apply:** `SELECT ... INTO #t` then join the temp tables, with a `DROP TABLE IF EXISTS
#t` before each. Narrow the set BEFORE joining rather than filtering after. Known remaining CTEs
to convert, in cost order: `Gold.usp_Load_Fact_Revenue` (8), `Gold.usp_Load_Dim_Date` (6),
`Gold.usp_Load_Dim_NHS_Contracts` (4), `Gold.usp_Load_Fact_Appointment_Journey` (3),
`Gold.vw_Fact_Appointment_Journey` (2), and one each in `Silver.usp_Load_Xero_Finance_Lines`,
`Gold.usp_Load_Fact_KPI_Snapshot`, `Gold.usp_Load_Fact_Invoices`, `Bronze.usp_Load_Recalls`.
Measure with `queryinsights.exec_requests_history` using **allocated_cpu_time_ms**, never
total_elapsed_time_ms — elapsed includes queue time and on a throttled capacity it measures the
symptom. Related: [[read-the-schema-before-querying-it]].

**To find what is actually burning the capacity**, attribute statements to jobs rather than reading them one by one: join `queryinsights.exec_requests_history` to `Audit.Process_Execution_Log` with `CROSS APPLY (SELECT TOP 1 ... WHERE q.start_time BETWEEN l.Start_Time AND l.End_Time ORDER BY l.Start_Time DESC)`, group by `Process_Name`, sum `allocated_cpu_time_ms`. On 2026-09-29 that showed two jobs were **63% of prod's warehouse compute** — `appdb_sync.access` 32.2% and `Gold.usp_Load_Dim_Date_Grouping` 30.6% — and neither was visible in the statement-level ranking, which was dominated by queue-inflated trivia like `SET @Run_Inserts = @My_Inserts;`. Note queryinsights has a few minutes' ingestion lag, so a measurement taken straight after a run is incomplete rather than good news.
