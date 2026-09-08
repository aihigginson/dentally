---
name: pbir-mobile-layout-model
description: How phone layouts work in these PBIP reports, and why bookmark navigation breaks on mobile.
metadata:
  type: project
---

Phone layout in PBIR is per-visual: `visuals/<id>/mobile.json` holding a
`position` on a **324px-wide** canvas. **A visual with no `mobile.json` is absent
from the phone entirely** - silently. Nothing warns you and the report still
publishes.

This is fatal here because the reports navigate by **bookmark**. A bookmark's
show/hide state applies on phone too, so a bookmark that reveals a visual with no
phone placement yields a blank screen - the switcher appears to do nothing. On
desktop the alternate bookmark states are **overlaid** (identical coordinates,
toggled); the phone layout must do the same, or you get an endless scroll with
gaps.

Baseline when this was found (2026-09-08): 36 failures across the 9 embedded
reports - 7 navigators with no phone placement, 12 dead bookmark states, 17
unreachable action buttons. Revenue's *detail* pages are the reference
implementation (100%, with phone-specific formatting overrides on the back
button). `Scripts/Check_Mobile_Layout.ps1` measures and gates all of it.
See [[pbir-json-must-be-utf8-no-bom]].
