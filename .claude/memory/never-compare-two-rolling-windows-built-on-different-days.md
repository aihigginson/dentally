---
name: never-compare-two-rolling-windows-built-on-different-days
description: "A release guard must re-derive a rolling-window figure from source, not diff it against a table built on an earlier day."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-06T18:05:00.000Z
---

**IT HAPPENED AGAIN ON 2026-10-06, HAVING READ THIS MEMORY.** V212 split Gold.Fact_Revenue into
four facts on PROD, snapshotting the old table as a baseline and asserting the variants matched it.
Invoice and NHS matched exactly; CAPITATION came back £2,263.47 high on an identical 441,771 rows.
Not a fault: capitation ACCRUES, because an open spell runs to `CAST(SYSUTCDATETIME() AS DATE)`.
Prod's last build was 05/10 21:23 and the split ran on 06/10, so every open member gained one
working day -- added to the segment row that already existed, which is why the ROW COUNT was
unchanged and only the money moved. The guard was comparing yesterday's aggregate to today's
rebuild, exactly as described below.

The fix that works: assert EXACT equality only where the figure cannot accrue (invoice lines,
NHS claims), and for anything time-dependent assert the shape instead -- rows exact, amount may
only have GROWN, and by less than one month. Bound it when you cannot re-derive it.

A guard that compares a freshly rebuilt rolling-window aggregate against the **previous**
version of that aggregate fails the moment the two were built on different days: the window
slides, and every row whose activity sat on the dropped day now differs. Re-derive the
figure from the facts over the window being checked instead.

**Why:** V188's first guard diffed the merged patient-value columns against V187's table and
failed on 1,485 of 33,837 patients. The loader was correct. V187's table was built on
26 Sept, V188 ran on the 27th, and 1,445 patients had revenue on 2023-09-26 with 113 an
attended visit — accounting for 1,444 value and 113 attendance differences exactly. I spent
a deploy cycle on a guard bug, and the same shape would have fired on any table-to-table
comparison of a `DATEADD(MONTH, -n, GETDATE())` window.

**How to apply:** before writing ANY release guard that reads a pre-change snapshot, ask what in
that figure moves with the clock. If anything does, exact equality is wrong and will fail on a
release that is perfectly correct -- mid-deploy, on prod, with the structural half already
applied. Then guard a derived column by recomputing it from its sources inside the guard,
over a window derived the same way the loader derives it. It is window-consistent, it keeps
working after the old table is dropped, and it is a stronger test — it re-derives the number
rather than agreeing with another copy of it. Leave the aggregation unfiltered where the
column is meant to be a total (`SUM(Amount)`, no `Revenue_Type` filter), so the guard also
catches a filter being reintroduced. Related:
[[calibrate-the-demo-tenant-against-live]].
