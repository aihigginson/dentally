---
name: a-rolling-window-straddles-two-financial-years
description: "Apportioning an annual target to Last 12 Months must sum each financial year's share; collapsing the window to one FY applies the wrong year's target and silently drops metrics targeted in the other."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-29T12:42:55.272Z
---

An annual target apportioned to a period is `annual x (working days in period / working days in
FY)` — but **Last 12 Months reaches back across the client's financial-year boundary**, so there
is no single FY to divide by. Collapsing the grouping to `MAX(d.Financial_Year)` fails two ways at
once:

1. it applies the **later** year's annual target across the whole window, and
2. a metric targeted in the **earlier** year only joins nothing and **vanishes entirely** —
   not a wrong number, an absent row.

The fix is a sum over the years the window touches, aggregated back to **one row per (node,
period, metric, role)**. Keeping the grain matters: measures read a target with `MAX` on some
metrics and `SUM` on others, so emitting a row per year would quietly halve every `MAX` one.

**Why:** found on 2026-10-29 replacing `Gold.Fact_Daily_Targets` (263,874 rows nightly) with
closed-form arithmetic in `Gold.usp_Load_Aggregate_Period_Targets`. Nine rows were wrong and
**every one was in Last 12 Months** — the all-in-one-period pattern is the tell for an FY-boundary
bug. `FY26` and `Last 3 Months` sat inside one year and looked perfect.

**How to apply:** when replacing an exploded table with arithmetic, **diff against the table you
are replacing before you delete it** — recompute the old loader's output from the still-present
rows and compare every (key, value) both directions. That diff is what caught this; reasoning
about the formula did not. Three counts to print: only-in-old, only-in-new, value-differs. A
0.0001 residual is fine and expected (the explosion rounded each daily value to 6dp then summed
hundreds of them; the ratio multiplies once).

Also: `Gold.vw_Dim_Date` labels an April–March year by its **END** year (FY2026 = Apr 2025 – Mar
2026), while the retired daily loader labelled the same NHS contract year by its **START** year.
Two conventions for one year, so never join a contract to a calendar on an FY label — join on
dates. Related: [[financial-years-differ-per-tenant]],
[[never-compare-two-rolling-windows-built-on-different-days]],
[[changing-a-fact-means-sweeping-its-derivations]].
