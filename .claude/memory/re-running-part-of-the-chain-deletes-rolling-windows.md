---
name: re-running-part-of-the-chain-deletes-rolling-windows
description: Running Dim_Date_Grouping without Dim_Date silently drops Last 3 Months and Last 12 Months from every period aggregate.
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-30T13:05:06.579Z
---

`Gold.usp_Load_Dim_Date_Grouping` used to hold **two notions of today**: `@Today` was the live
clock, while the rolling windows are bounded by `Gold.Dim_Date.Relative_Day`, which is only as
current as the last `Gold.usp_Load_Dim_Date` run.

When they disagree the FY bucket runs to a later date than `Last 3 Months` and `Last 12 Months` do.
`Gold.usp_Load_Aggregate_Period_Targets` keeps only the groupings that reach the latest date any
grouping reaches — so **both rolling windows are discarded, silently**. On DEV, 30 Oct 2026:
`Relative_Day = 0` was the 28th, and 1,257 target rows became 508 with no error.

Fixed 30 Oct 2026 — `@Today` is now taken from `Relative_Day = 0`, so the proc is internally
consistent whatever the calendar's age.

**Why it still matters:** the same two-clock split exists wherever a proc mixes `SYSDATETIME()`
with a stored `Relative_Day`. It never bites during a full nightly build (both procs run on the
same day) and always bites when part of the chain is re-run by hand.

**How to apply:** after re-running any date-dependent loader on its own, check that
`Gold.Aggregate_Period_Targets` still has all three `Date_Grouping` values before trusting a report.
Related: [[a-rate-has-no-group-target-unless-entered-there]],
[[never-compare-two-rolling-windows-built-on-different-days]].
