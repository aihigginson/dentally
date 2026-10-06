---
name: sort-a-month-on-month-commencing-date
description: "List Date[Month Year] is text with no sort column; sort a month axis on Month Commencing Date, which is a real date, and format it MMM yyyy."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-06T14:28:07.138Z
---

`PBI_Dentally.csx` sets **`SortByColumn` on exactly one column** in the whole model (`Category` on
the bucket table). `List Date[Month Year]` is plain text with nothing behind it, so a visual that
shows it gets alphabetical order.

Sorting such a visual on `List Date[Calendar Year Month]` does **not** fix it — a `sortDefinition`
naming a column the visual does not **project** is silently dropped, and the months come out in no
order at all. Symptom: a matrix showing Aug-2026 above Jul-2026 while the detail table beside it
starts in October, which reads as "the detail doesn't match the selection".

**How to apply:** project `List Date[Month Commencing Date]` (a real datetime, the 1st of the month),
sort the visual on that same column, and give the projection `"format": "MMM yyyy"` so it reads
"May 2026". `Finance.Report` has done this all along — check how a working visual does it before
inventing a sort.

Related: [[a-table-projection-takes-no-displayname]] (the other way a sort breaks a visual silently),
[[get-data-bakes-a-literal-endpoint-into-the-model]].
