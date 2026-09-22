---
name: sql-files-are-mostly-utf8-not-utf16
description: "CLAUDE.md says all SQL is UTF-16 LE; only 46 of 380 Fabric/*.sql actually are, and grep silently skips those, so content searches miss real files."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-22T10:45:54.057Z
---

**CLAUDE.md's "All SQL files use UTF-16 LE with BOM" is out of date.** Measured on 2026-09-22
across `Fabric/*.sql`: **292 plain UTF-8, 42 UTF-8 with BOM, 46 UTF-16 LE** of 380. The UTF-16
ones are the older SSMS-scripted objects; everything added since is UTF-8.

`Scripts/Deploy.ps1` reads with `[System.IO.File]::ReadAllText($path)` and no encoding argument,
so .NET sniffs the BOM and all three work. **Match the file's direct peers, not the CLAUDE.md
line** — e.g. a new `Gold.Aggregate_*.Table.sql` goes next to UTF-8 peers, so write UTF-8.

**The trap that actually costs time:** `grep`/`Grep` does not match inside the UTF-16 files, so a
content search reports "no matches" for text that is plainly there. On 2026-09-22 this hid
`Gold.Dim_Patient_Data_Quality.View.sql` from a search for `Data_Quality`, and I nearly rebuilt a
feature that already existed. **Always cross-check a content search with a filename glob** before
concluding something is not in the repo.

Also: **Fabric Warehouse rejects `tinyint`** outright ("not supported in this edition"). Use
`smallint`.

See [[pbir-json-must-be-utf8-no-bom]] for the opposite rule on the report side.
