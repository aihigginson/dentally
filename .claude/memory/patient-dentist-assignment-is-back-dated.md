---
name: patient-dentist-assignment-is-back-dated
description: "Fact_Revenue_Capitation credits every month of a spell to the patient's CURRENT dentist, so historical per-practitioner plan revenue is wrong whenever a list changes hands."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-20T21:27:02.945Z
---

`Gold.usp_Load_Fact_Revenue` builds `#spell` with `pat.Dentist_Practitioner_ID` taken from
`Gold.Dim_Patients` -- one **current-state** value, carried across a spell that runs from
tenure start to today. `Dim_Patients` is a MERGE upsert with no history, so there is no
record of who the patient's dentist used to be.

Consequence: when a list moves between dentists, the receiving dentist is retrospectively
credited with that patient's capitation back to the start of the spell, and the previous
dentist loses it.

Measured on Maple, David Mason 2026 (his plan list roughly tripled over the year). Our
figure is flat because it is computed from today's list; theirs is what was really paid:

    month    Jan    Feb    Mar    Apr    May    Jun    Jul    Aug    Sep
    ours   15994  16028  16078  16052  16071  15973  16010  15970  15971
    theirs  5271   6065   7908  12904  14281  15876  15912  15827  15678

432-434 patients at ~£37 every month, unchanged. January is 3x overstated and the series
converges only once the real list catches up with the current one. The same artefact
drags the hygienist cross-charge (ours exceeded theirs by 1172, 721, 714, 536 in Jan-Apr,
then 153, 134, -153, -258) because its visits are filtered on the same current
assignment.

**Why:** this is a different fault from [[capitation-is-an-estimate-not-observed-income]].
That one is about the VALUE being reconstructed; this is about the ATTRIBUTION being
back-dated. A practice with stable lists never shows it, which is why it survived a year.

**How to apply:** never present per-practitioner plan revenue, or anything filtered on
`Dim_Patients.Dentist_Practitioner_ID`, as a historical fact -- it is "what this month
would look like if today's list had always applied". Practice-level totals are unaffected.
Fixing it needs an effective-dated patient-to-dentist history, which Dentally may not
expose. Related: [[who-counts-as-a-plan-patient]],
[[the-cross-charge-exists-for-hygienist-pound-per-hour]],
[[changing-a-fact-means-sweeping-its-derivations]].
