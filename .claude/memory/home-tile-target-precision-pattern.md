---
name: home-tile-target-precision-pattern
description: "How to set decimal places on a Home KPI tile's target line in PBIR - and the field id must be copied, never invented."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-10T07:33:31.082Z
---

The small target line under a Home KPI tile (`£423K`, `5K`) is `objects.referenceLabelValue`.
To give one 1dp, APPEND an entry to that array:

```json
{
  "properties": { "valuePrecision": { "expr": { "Literal": { "Value": "1L" } } } },
  "selector": { "metadata": "_Measures.Total Revenue",
                "id": "field-28b88d63-8dc5-fb05-1f60-342f26fa6710" }
}
```

**==> THE id IS COPIED, NOT INVENTED. <==** It is the field id Desktop already assigned to that
measure's entry in `objects.referenceLabel` (the entry whose `value` is the target measure). Find
it by matching on `selector.metadata`; every Home tile that shows a target has one. The
`referenceLabelValue` array also holds a bare `{metadata}` placeholder per measure with no
properties and no id — that is NOT the one to copy from, and it is not where the setting goes.
`data` and `order` are not needed on the new entry.

**Also:** my earlier note that `referenceLabelValue` accepts only `show`, `textWrap`,
`valueFontFamily`, `valueFontSize` and `valueItalic` was wrong — `valuePrecision` is accepted.
The convention is `value<Thing>`, so the display-units property is probably `valueDisplayUnits`,
NOT the `labelDisplayUnits` I invented (Power BI discarded that silently on first open — 285
deletions — and `Check_PBIR.py` passed it because the shape is structurally valid). Do not guess
again: set it once in Desktop's formatting pane, save, and read the real name out of the diff.
That is how this one was learned. See [[pbir-json-must-be-utf8-no-bom]].

## A measure can own SEVERAL reference-label ids — pick by `value`, never by name

`Total Revenue` has FOUR on the Revenue cards: the live one at `order=1`, a `vs Target` one at
`order=0`, and two EMPTY leftovers at `order=2`. Building `{metadata: id}` as a dict silently keeps
the last, so precision landed on a leftover: valid JSON, passes `Check_PBIR.py`, renders nothing.
The symptom was the Revenue target still reading `£2M` while its neighbours showed a decimal.

**The live id is the `referenceLabel` entry whose `value` is the measure `"<Measure> Target"`.**
Match on that, not on `selector.metadata` and not on `order`. Audit afterwards by re-deriving the
live id per measure and asserting every `valuePrecision` entry points at it — a wrong id cannot be
seen in a diff, only in the rendered report.
