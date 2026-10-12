---
name: financial-years-differ-per-tenant
description: "Maple's financial year is the calendar year, the demo tenants' is April-March, so \"FY\" has no shared meaning across tenants and a group view can only offer rolling windows."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-12T15:36:57.348Z
---

Measured 2026-10-12 from `PBI.[List Date Grouping]` joined to `List Date`:

```
t100 (Maple)  FY26     2026-01-01 .. 2026-12-31   calendar year
t11 / t12     FY26-27  2026-04-01 .. 2027-03-31   April-March
shared        Last 3 Months / Last 12 Months -- identical dates for every tenant
```

Different PERIODS, not different labels for one period. `Input.Targets.FY` is already consistent
(the year the FY ENDS: Maple 2026, demo 2027), so this cannot be fixed with a stable key — the
year-end is a real property of the practice.

**Why:** it is a second, independent reason multi-practice is SELECTION not aggregation. Even if
[[group-target-aggregation-is-unresolved]] were solved, a cross-tenant "FY26" would be summing
Maple's calendar year against another practice's April-March year under one label.

**How to apply:** a cross-tenant view may offer only tenant-agnostic periods — `Last 3 Months`,
`Last 12 Months`, or calendar months — never FY, unless every practice in the group shares a year
end. Worth asking at onboarding. `List Date Grouping` is a bridge (tenant x grouping x date) with
NO unique column, so it can never be the one side of a relationship; tenant-filter it with an RLS
rule, not a join, and watch for [[rls-m2m-truncates-list-date]] since it needs bidirectional
filtering.
