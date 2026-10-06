---
name: sunday-is-devs-weekly-build-day
description: "Sunday puts two full builds in one 24h window, and the capacity figure is a trailing 24h total that idleness cannot lower."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-04T22:12:58.381Z
---

The scheduled background floor, which runs whether or not anyone touches anything:

        PROD  Delta_Build_Nightly   DAILY   22:00 GMT    ~23 min of warehouse work
        DEV   Delta_Build_Nightly   WEEKLY  18:00 Sunday ~22 min
        BOTH  appdb_sync.access     every 10 min         144 runs/day each
        BOTH  caj-sales-monitor     daily 06:40 UTC

Normal day ≈ 40 min of ETL across both warehouses. **Sunday ≈ 74 min**, because dev's weekly build
lands in the same 24-hour window as prod's nightly.

**Why it cannot come down by waiting:** background operations smooth over **24 hours** (interactive
over 5 minutes). So a build at 17:03 is still being amortised into "Last 24 hours" until 17:03 the
NEXT day. The figure is a trailing total, not a live reading — sitting idle changes nothing, and the
"I haven't touched anything" instinct is exactly backwards.

**How to apply:** before treating a high percentage as a problem, read the three counters next to
it — **# Throttled / # Interactive rejected / # Background rejected**. All zero and Health "Healthy"
means the capacity absorbed the load; the percentage alone is not an incident. Compare the 24-hour
figure against the 7-day one too: on 2026-10-04 it was 73.94% against a 7-day 81.92%, i.e. BELOW the
recent norm, because the 7-day window still held the 2026-10-01 demo reseed (127 min in dev alone)
and the 10-02 "act as" break test. Those decay out on their own. Diagnose from
`Audit.Process_Execution_Log` (`Audit.Orchestrate_Build` duration per day), not from the metrics
app, whose CU measures are not reachable over executeQueries. Related:
[[a-report-render-costs-about-27-cu-seconds]], [[metrics-app-health-is-live-compute-is-a-nightly-import]],
[[act-as-reloads-and-re-embeds-ten-reports]], [[scale-target-is-100-practices]].
