---
name: desktop-error-list-is-stale-until-you-save
description: "Power BI Desktop's \"Objects with errors\" dialog does not re-validate after Tabular Editor writes to the model — it shows the state before the script ran. Save, then look again."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-29T19:57:19.907Z
---

**Power BI Desktop's "Objects with errors (N)" list does not refresh when an external tool changes
the model.** It keeps showing what was wrong BEFORE the script ran. **Save the file and the
errors clear.**

**Why:** 2026-10-29. `Gold.Aggregate_Period_Targets` was re-keyed (`[Target Level]` → `[Role]`),
`PBI_Dentally.csx` was swept and re-run, and Desktop still reported **152 objects with errors**,
every one *"Column 'Target Level' in table 'Aggregate Period Targets' cannot be found"*. The csx
had in fact worked on the first run. Saving cleared all 152.

**How to apply — the tell is a contradiction, so look for it before chasing anything:**

A script that sweeps the model and reports **0 to repair** while Desktop still shows errors is
not a failed script. Ask which of these it is, in this order:

1. **Stale list** — Desktop has not re-validated. *Save first.* This is the common one.
2. **Wrong model** — Tabular Editor connected over XMLA to the published dataset while Desktop
   holds its own local copy. Both are "the model"; only one has the problem.
3. **Not a measure** — expressions also live in calculated columns, calculated tables,
   calculation items, KPI status/trend/target, detail-rows expressions and RLS filters. A
   measure-only sweep reports 0 and is not wrong, just blind.

`Scripts/Find_Broken_Expressions.csx` distinguishes all three: it prints the model name and table
count first (settles 2), scans every expression-bearing object type (settles 3), and finding
nothing settles 1.

==> **DO NOT DELETE `_Measures` TO "REBUILD IT FROM SCRATCH".** <== Tempting when the error count
will not shift, and it would have destroyed work here for no reason. The csx deletes per
`DisplayFolder` before re-adding and its `__owned_before` block REPORTS any measure it did not
rebuild; deleting the table by hand skips that warning, and the measures it does not own are
exactly the ones nobody notices are gone until a report breaks at a practice. See
[[the-csx-owns-only-the-measures-table]].

Related: [[a-vw-override-silently-drops-new-columns]] — the genuine version of this failure, where
a PBI view really is missing a column the model needs.
