---
name: a-table-projection-takes-no-displayname
description: "CORRECTED: displayName on a tableEx is fine (15 working examples). The thing that breaks a table is sorting on a field it does not project."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-06T13:55:47.725Z
---

**This memory previously said a `displayName` on a `tableEx` projection silently drops the column.
That was wrong.** Counted across the repo's working reports on 2026-10-06: `displayName` appears on
**15 tableEx projections**, 92 cardVisual, 2 slicer. Desktop opens all of them.

What actually happened on 2026-10-05: a published table rendered `Client Name` alone, all eight
measure columns gone. I changed **three** things at once and credited the wrong one.

        removed displayName from the projections     <-- blamed this; it was innocent
        removed `active` from the column projection
        changed the sort from [Days Since Last Access] to a PROJECTED column

**The sort is the likely culprit.** That measure was not in the visual at all. A non-projected
*column* of a table already in the visual is fine — Day_Book and Patient both do it — but a measure
the visual never asks for is a different thing.

**How to apply:** when a PBIR visual misbehaves, change ONE thing and re-publish. Three at once and
you learn nothing except that some combination works, which is how a wrong rule gets written down
and then followed for weeks. And before copying a key into hand-written PBIR, check the LEVEL as
well as the name — `filterConfig` is a sibling of `visual`, not a property of it, and nesting it
stopped Desktop opening the report entirely. `Scripts/Check_PBIR.py` now validates both.
Related: [[pbir-json-must-be-utf8-no-bom]], [[a-detail-table-needs-a-column-not-a-measure]].
