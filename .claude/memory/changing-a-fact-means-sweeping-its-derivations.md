---
name: changing-a-fact-means-sweeping-its-derivations
description: V197 changed what Revenue_Type means and left usp_Load_Fact_Metric_Actuals deriving NHS from a condition it had just made unreachable - nhs_revenue read 0.00 for three months.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-01T20:20:16.901Z
---

V197 stopped loading NHS invoice lines and gave NHS its own `Revenue_Type` at the UDA value. It
updated `Fact_Revenue`, the dependent aggregates and the DAX. It did **not** touch
`Gold.usp_Load_Fact_Metric_Actuals`, which kept deriving NHS as
`CASE WHEN NHS_Charge > 0 ... END` over `Revenue_Type = 'Invoice'` — a condition V197 had just
made impossible, since Invoice rows are now filtered to `ISNULL(NHS_Charge,0) = 0`.

No error. `nhs_revenue` became structurally `0.00` for every tenant, `private_revenue` absorbed
it, and `total_revenue` silently meant invoice-only. Fixed by V201 on 2026-10-01, found only
because seeding onboarding targets produced an NHS target of zero for a practice with real NHS
income.

**Why:** the dangerous change is not a renamed column — that breaks loudly. It is **narrowing or
repartitioning what an existing value means** while every dependent expression still compiles and
still returns a number. `NHS_Charge > 0` went from "this is the NHS slice" to "never true", and
nothing anywhere complained.

**How to apply:** when a release changes a type/category/flag's *meaning* rather than its shape,
grep every procedure for the predicate that encoded the old meaning — here `NHS_Charge`,
`Revenue_Type` — not just for the table name, and check each hit still means what it meant. Two
specific traps: `grep` silently skips the UTF-16 files (see
[[sql-files-are-mostly-utf8-not-utf16]]), which is exactly why this one was missed; and a
procedure whose header claims it "MIRRORS the live DAX" as a reconciliation oracle is asserting an
invariant that a release can quietly break. Prefer a guard that asserts the mirror
(total = sum of its parts, and the parts against the source) over trusting the comment. Related:
[[nhs-income-is-the-uda-value]], [[verify-aggregation-changes-on-two-tenants]].

**2026-10-06, the sharper version: RENAMING an object breaks readers a release never executes.**
V211/V212 split Gold.Fact_Revenue into four tables, dropped the table and shipped the consolidated
view as `Gold.vw_Fact_Revenue`. Four procedures read `Gold.Fact_Revenue` by name. Every release
guard passed -- they verified the FACT -- and the next nightly build failed:

        usp_Load_Aggregate_Site_Patient_Practitioner_Daily   Invalid object name 'Gold.Fact_Revenue'
        usp_Load_Aggregate_Practitioner_Contribution         Invalid object name 'Gold.Fact_Revenue'
        usp_Load_Aggregate_Site_Patient_Current              Invalid object name 'Gold.Fact_Revenue'
        usp_Load_Fact_Metric_Actuals                         never ran -- Kahn blocks a failed job's dependents

A manifest that deploys and verifies a fact does not execute its consumers, so nothing could catch
it. One of the four was also missed by `grep` because that file is UTF-16 -- see
[[sql-files-are-mostly-utf8-not-utf16]]. The fix was to give the view the name its readers already
use; `vw_` exists only to supersede a table of the same name, and there was no longer a table.

**So: a release that renames, drops or replaces a Gold object MUST run its consumers as a step, not
merely assert the object's own shape.** V214 does exactly that and is the template.
