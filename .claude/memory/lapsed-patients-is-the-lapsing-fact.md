---
name: lapsed-patients-is-the-lapsing-fact
description: Gold.Fact_Lapsed_Patients already holds the lapsing population; the customer-facing lapsed figures do NOT come from it.
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-24T21:44:09.063Z
---

`Gold.Fact_Lapsed_Patients` is patient grain with `fk_Practitioner`, `fk_Practice_Site`,
`fk_Payment_Plan` and a dated event — it IS the lapsing fact. `Lapsed_Type` now carries
`'Set as inactive'` / `'Calculated as inactive'` / `'At Risk'`, and **`Is_Lapsed`** separates
them: count lapsed patients with `SUM(Is_Lapsed)`, never `COUNT(*)`.

The customer-facing lapsed numbers do **not** read this fact. `lapsed_patients`,
`lapsed_deactivated` and `lapsed_calculated` are computed in
`Gold.usp_Load_Fact_KPI_Snapshot` straight off `Dim_Patients` date fields into
`Fact_Metric_Actuals`, and `[Lapsed Patients]` / `[Net Patient Growth]` read that aggregate.
Only two visuals on the Patient page bind `_Lapsed Patients` — the alluvial and the patient
list it drills to.

**Why:** I built `Fact_Patient_Lapse_Flow` as a "separate fact with a wider population",
justified in its own header by a claim that extending the existing one would move a
customer-visible number. It wouldn't, and 2,300 of its 3,467 rows were the same patients with
the same keys and the same status counts. Owner caught it: "Why didnt you use _Lapsed Patients
instead of creating Patient Laps Flow." Retired in V243.

**How to apply:** before adding a patient-lifecycle fact, check `Fact_Lapsed_Patients` first,
and establish which table a figure actually comes from before arguing a change would move it.
The at-risk rung's date is last-reminded + 60 days — the ladder's own test in
`Gold.usp_Load_Dim_Patients`; `Dentist_Recall_Date` is the NEXT recall and is the wrong date.
See [[read-the-schema-before-querying-it]], [[a-warehouse-guard-cannot-see-the-model]].
