---
name: a-bookmark-lists-the-visuals-it-applies-to
description: PBIR bookmarks carry targetVisualNames; a visual not on that list ignores the bookmark entirely.
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-25T09:38:04.126Z
---

A PBIR bookmark has `options.applyOnlyToTargetVisuals: true` and `options.targetVisualNames`,
an explicit list of visual ids captured when Desktop made the bookmark. **Adding an entry to
`explorationState.sections[*].visualContainers` does nothing for a visual whose id is not also
in `targetVisualNames`** — the bookmark declines to apply to it, so it keeps the page default
(`isHidden`), silently, on every bookmark.

Add a new visual to a bookmarked page and you must write the id in **both** places.

`options.suppressData: true` (the Patient report's setting) means a bookmark captures display
state only, so switching bookmarks does **not** reset a cross-filter.

**Why:** a Patient Category slicer and two buttons stayed invisible on every tab through
several rounds of debugging, while edits to existing visuals took effect immediately. Ruled
out first, all wrongly: file validity, page registry (`page.json` has none — visuals are
folder-discovered), structure, publish state.

**How to apply:** it is a registry like [[pbir-enums-are-validated-and-fail-closed]] territory
— state without registration is ignored rather than erroring. Assert the invariant both ways:
every visual a bookmark holds state for is on its target list, and every targeted id exists on
the page.
