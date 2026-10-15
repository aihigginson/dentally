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

**Three constraints that decide HOW, found by doing the sweep:**

1. **A VIEW cannot reference a temp table at all** — a SQL Server/Fabric rule, so the conversion
   simply is not available in a view definition. Where the view's CTE is read ONCE as a relation,
   a derived table is exactly equivalent and is the CTE-free form to use. Beware of counting
   references by name: `ten` in `vw_Dim_Date` looks like 11 references but 10 are COLUMN uses
   (`ten.M`) and it is joined once.
2. **Fabric rejects CROSS JOIN between two temp tables.** `Gold.usp_Load_Fact_KPI_Snapshot` kept
   a CTE deliberately for this reason and said so. Rewrite as `INNER JOIN ... ON <the WHERE
   predicates>` — identical relation, and temp-to-temp INNER/LEFT joins are used ~145 times in
   this repo. There is not one `CROSS JOIN #temp` anywhere, which is the evidence it is real.
3. **A CTE is statement-scoped; a temp table is SESSION-scoped.** So a procedure called twice in
   one session fails on `SELECT ... INTO #t` the second time. Guard every one.

**The one deliberate exception:** `Gold.Dim_Patient_Data_Quality` keeps its `pat` CTE, read as a
relation three times across three UNION ALL branches. A view cannot take a temp table, and
inlining would copy 37 lines three times AND still evaluate three times. It wants to be a
materialised table loaded by a procedure — an architecture change, not a tidy-up. The file says
so in place.

**How to apply:** `SELECT ... INTO #t` then join the temp tables, with a `DROP TABLE IF EXISTS
#t` before each. Narrow the set BEFORE joining rather than filtering after.

**SWEPT 2026-10-13 — the list is done.** All 14 remaining WITH-clauses were converted in one pass
(branch `refactor/no-ctes`): Billing.usp_Generate_Invoice_Lines (12), Fact_New_Patients (5),
Fact_Revenue (8 across two blocks), Dim_NHS_Contracts (4), Fact_Appointment_Journey (3), plus one
each in Fact_Invoices, Fact_KPI_Snapshot, Xero_Finance_Lines, vw_Dim_Date,
vw_Fact_Appointment_Journey and Seed_Targets_From_Actuals.py. Grep alone under-reports: four of
the files are UTF-16 and ripgrep skips them silently ([[sql-files-are-mostly-utf8-not-utf16]]).
Measure with `queryinsights.exec_requests_history` using **allocated_cpu_time_ms**, never
total_elapsed_time_ms — elapsed includes queue time and on a throttled capacity it measures the
symptom. Related: [[read-the-schema-before-querying-it]].

**To find what is actually burning the capacity**, attribute statements to jobs rather than reading them one by one: join `queryinsights.exec_requests_history` to `Audit.Process_Execution_Log` with `CROSS APPLY (SELECT TOP 1 ... WHERE q.start_time BETWEEN l.Start_Time AND l.End_Time ORDER BY l.Start_Time DESC)`, group by `Process_Name`, sum `allocated_cpu_time_ms`. On 2026-09-29 that showed two jobs were **63% of prod's warehouse compute** — `appdb_sync.access` 32.2% and `Gold.usp_Load_Dim_Date_Grouping` 30.6% — and neither was visible in the statement-level ranking, which was dominated by queue-inflated trivia like `SET @Run_Inserts = @My_Inserts;`. Note queryinsights has a few minutes' ingestion lag, so a measurement taken straight after a run is incomplete rather than good news.

**Validate offline, with the real parser.** SSMS 22 ships ScriptDom at
`C:\Program Files\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\Extensions\Application\Microsoft.SqlServer.TransactSql.ScriptDom.dll`
— load it in PowerShell, pick the newest `TSql###Parser` (TSql180Parser today), and parse each file
read with ITS OWN encoding. That caught a malformed view rewrite (orphaned CTE body left behind
while a copy was also written into the FROM) with no capacity spent at all. A refactor of this
shape is reviewable without a single query.

==> **FROM A CLIENT, A TEMP TABLE DOES NOT SURVIVE BETWEEN `cur.execute()` CALLS.** <== I wrote
the opposite here on 2026-10-14 -- "survives because the connection is autocommit and
long-lived" -- and it is FALSE. `Scripts/Seed_Targets_From_Actuals.py` failed outright the first
time it was run:

```
pyodbc.ProgrammingError 42S02 -- Invalid object name '#base'
```

A temp table inside a stored PROCEDURE is fine, because the body is ONE batch -- which is what
all 222 working `SELECT ... INTO #t` cases in this warehouse are. Spreading one across separate
round-trips from Python is a different thing and does not work.

**So from a client, convert a single-reference CTE to a DERIVED TABLE, not a temp table** -- the
same answer the views needed, and for the same reason. Nothing caught this for a day because the
script is not in the regression suite, so it would have broken the next onboarding.
