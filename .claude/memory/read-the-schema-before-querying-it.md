---
name: read-the-schema-before-querying-it
description: Stop guessing column names in this warehouse - the naming is inconsistent between layers and a wrong guess costs a round trip every time.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T23:27:49.641Z
---

Query `INFORMATION_SCHEMA.COLUMNS` first whenever writing against a table not already open in
context. The naming does not generalise between layers, and guessing has cost a failed round
trip on nearly every attempt.

**Why:** on 2026-09-27 I guessed wrong at least six times in one session —
`Audit.Process_Log` (the table is `Audit.Process_Execution_Log`), `Process_Code` on that log
(it keys on `Process_Name`, the SP, not the config code), `DW_Loaded_At` on Silver (Bronze has
`DW_Loaded_At`, Silver has `DW_Created_At`/`DW_Updated_At`), `Site_Name` on `Silver.Sites` (it
is `Name`; only Gold renames it), `First_Appointment_Date` on `Silver.Patients` (it lives on
`Patient_Stats`), and `Silver.Appointments.Id` (it is `Appointment_ID`). Two of those landed
**inside release guards**, so a manifest failed mid-deploy with the real work already applied.

**How to apply:** one cheap `INFORMATION_SCHEMA` lookup before writing the query, and always
before putting a column name inside a release manifest — a guard that cannot compile is worse
than no guard, because it fails the release after the changes are live. Known traps: Bronze
`DW_Loaded_At` vs Silver `DW_Created_At`; business keys are `<Entity>_ID` in Silver and
`bk_<Entity>_ID` in Gold; friendly names with spaces exist only in the PBI views. Related:
[[fabric-collation-is-case-sensitive]].
