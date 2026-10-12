---
name: a-silent-except-froze-patient-stats
description: "Ingest_Dentally's patient_stats block sits outside the logged loop; a NameError there froze the stage table for three months behind a job reporting Completed."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-12T14:28:19.292Z
---

`Ingest_Dentally.ipynb` handles `patient_stats` in a block AFTER the main entity loop, because
Dentally's bulk pagination is broken and the rows need gap-filling one patient at a time. That
block had two defects that compounded (both fixed 2026-10-12):

1. `inc` was referenced by its two `fetch_all` calls and **bound nowhere** — so the block raised
   `NameError` on every run from ~2026-07-09.
2. Unlike every entity in the loop, it never called `log_ingest`, so the failure was a `print`
   inside a bare `except` and vanished.

`write_stage` was therefore never reached. `stage_patient_stats` froze, and the nightly Bronze
MERGE kept re-merging that stale stage and reporting SUCCEEDED. Diagnosis clue: the damage stopped
at a clean patient id (27,954), because a frozen stage cuts exactly where it stopped — a drifting
bug scatters.

**Why it matters:** `Dim_Patients.First_Appointment_Date` and the Last/First exam and appointment
dates all come from this one feed. Maple's New Patients read 16 for a quarter in which 102
patients registered, and Patient Growth was wrong by the same number. The customer spotted it; no
monitoring did.

**How to apply:** a Fabric job reporting Completed proves nothing about the entity inside it —
check `Audit.Ingest_Log` per entity. Any ingest block outside the logged loop is invisible by
construction. And when a gap has a sharp boundary in a monotonic key, suspect a frozen writer, not
a drifting filter. See [[piping-to-tail-hides-the-exit-code]] and [[read-the-schema-before-querying-it]].
