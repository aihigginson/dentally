---
name: a-short-action-button-needs-container-padding
description: A PBIR actionButton under ~40px collapses to a coloured line unless visualContainerObjects.padding is reduced.
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-25T14:05:44.431Z
---

A PBIR `actionButton` carries default container padding sized for a tall button. In a short
one (28px, e.g. the slicer row) that padding consumes the whole height and the button renders
as **a few-pixel line of its own fill colour** — correctly positioned, correctly coloured,
fully clickable, and invisible.

The fix is `visual.visualContainerObjects.padding` → `{top: 3D, bottom: 3D}`. Note it lives in
**visualContainerObjects, not visual.objects**, so nothing changed in the `icon` / `fill` /
`text` / `outline` blocks will ever move it.

**Why:** a "Full screen list" button spent four rounds being rebuilt — blocks cloned from a
working 250x59 donor, `shape` dropped, fill recoloured from pale to navy — all of which were
fine. The owner found it in Desktop in one go: *"It was the padding."*

**How to apply:** "a thin line you can click" is a styling symptom, not a structural one —
check height against padding before touching the object blocks. Related:
[[a-table-projection-takes-no-displayname]],
[[a-bookmark-lists-the-visuals-it-applies-to]].
