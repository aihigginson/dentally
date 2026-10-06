---
name: fabric-collation-is-case-sensitive
description: "Fabric Warehouse defaults to Latin1_General_100_BIN2_UTF8, so LIKE and = are case-sensitive - lowercase both sides when matching text."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T10:15:57.908Z
---

Fabric Warehouse's default collation is `Latin1_General_100_BIN2_UTF8`, which is **binary and
case-sensitive**. `LIKE '%estimate%'` does not match `'AN ESTIMATE'`, and `=` comparisons on
text behave the same way. This is the opposite of the case-insensitive default most SQL Server
databases use.

**Why:** on 2026-09-27 a V191 release guard asserting that a glossary entry mentioned the word
"estimate" failed, even though the text opened with `AN ESTIMATE, NOT OBSERVED INCOME`. The
wording was right; the guard was case-sensitive.

**How to apply:** wrap both sides in `LOWER()` for any text match that is not an exact,
known-case key — release guards, search filters, status comparisons. Where status strings are
compared, prefer listing the real variants (the recall loader already does
`IN ('sent','completed','Sent','Completed')` for this reason) or lowercase the column.
