---
name: patient-dentist-assignment-is-back-dated
description: Fact_Revenue_Capitation credits every month of a spell to the patient's CURRENT dentist, so historical per-practitioner plan revenue is wrong whenever a list changes hands.
metadata:
  type: project
---

`Gold.usp_Load_Fact_Revenue` builds `#spell` with `pat.Dentist_Practitioner_ID` taken from
`Gold.Dim_Patients` -- one **current-state** value, carried across a spell that runs from
tenure start to today. `Dim_Patients` is a MERGE upsert with no history, so there is no
record of who the patient's dentist used to be.

Consequence: when a list moves between dentists, the receiving dentist is retrospectively
credited with that patient's capitation back to the start of the spell, and the previous
dentist loses it.

Measured on a live tenant against a practice's own pay sheets, for a practitioner whose
plan list grew substantially over a year: our figure is flat -- the same patient count at
the same rate every month, because it is computed from today's list -- while theirs starts
at roughly a third of that and converges with ours only once the real list catches up.
The same artefact drags the hygienist cross-charge, whose visits are filtered on the same
current assignment, and the gap there shrinks month by month until it crosses.

**Why:** this is a different fault from [[capitation-is-an-estimate-not-observed-income]].
That one is about the VALUE being reconstructed; this is about the ATTRIBUTION being
back-dated. A practice with stable lists never shows it, which is why it survived a year.

**The history IS recoverable, just not from Dim_Patients.** `Gold.Fact_Appointments`
records which practitioner actually saw a patient on the day, so who treated whom over
time can be reconstructed from attendance. That is how the Ian Hunt handover was measured
(he last treated a patient on 2026-03-31; 548 of his patients then met a new dentist, and
36.7% never returned against 23.7% for those dentists' own patients). Use appointments for
any "who was their dentist then" question.

**How to apply:** never present per-practitioner plan revenue, or anything filtered on
`Dim_Patients.Dentist_Practitioner_ID`, as a historical fact -- it is "what this month
would look like if today's list had always applied". Practice-level totals are unaffected.
Fixing it needs an effective-dated patient-to-dentist history, which Dentally may not
expose. Related: [[who-counts-as-a-plan-patient]],
[[the-cross-charge-exists-for-hygienist-pound-per-hour]],
[[changing-a-fact-means-sweeping-its-derivations]].
