---
name: a-detail-table-needs-a-column-not-a-measure
description: Swapping a column for a measure in a Power BI detail table destroys its row grain - auto-exist is lost and every combination the measure is non-blank for survives.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T09:18:05.281Z
---

In a table visual built only from **columns**, the query auto-exists: it returns the
combinations that actually occur together. Add a **measure** and it becomes
`SUMMARIZECOLUMNS` over those columns keeping every combination where the measure is
non-blank — so a measure that does not depend on the table's filter context multiplies the
rows out.

**Why:** on 2026-09-27 I replaced `List Patients[Total Paid]` with the measure
`_Measures[Patient Value 3yr]` in the three Day Book detail tables. The measure reads
`Aggregate Site Patient Current`, filtered by the patient but not by the appointment or the
cancellation reason — `List Patients -> _Appointments` is single-direction, so a reason
filter never reaches the patient. Every patient × reason pair was therefore non-blank:
Cancellations Detail showed one patient against all 18 reasons and totalled £5,625,663
against 90 real cancellations. It shipped to prod. The tiles beside it (90 / 77) stayed
correct, which made it read as a data fault rather than a visual one.

**How to apply:** when a per-row attribute is wanted in a detail list, use a COLUMN on the
dimension the list is already grouped by — a calculated column via `AddCalculatedColumn` in
`Fabric/PBI_Dentally.csx` if the number lives on another table
(`CALCULATE ( SUM ( 'Other Table'[Col] ) )` from the one side). Keep the measure for genuine
aggregation contexts such as a tooltip or a card. Before swapping any field in a `tableEx`,
check whether the existing reference is `"Column"` or `"Measure"` in the visual.json and keep
the same kind. Related: [[get-data-bakes-a-literal-endpoint-into-the-model]].
