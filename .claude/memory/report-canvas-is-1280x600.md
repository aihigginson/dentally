---
name: report-canvas-is-1280x600
description: "Every embedded report page is 1280x600 (ratio 2.133) to match the app viewport, with FitToPage and an aspect-ratio container; the Template was the source of 1280x720 drift."
metadata:
  type: project
---

**The standard is 1280x600.** After the app's own header, trial banner and tab bar (~130px),
a real viewport is about 2.0-2.14 wide-to-tall. 1280x600 is 2.133 -- a 0.4% mismatch on a
1366x768 laptop. 1280x720 is 1.778, roughly 18% too tall, and that was the constant
scrolling the owner called "really infuriating".

**The Template was the source.** Eight of its nine pages were 720, so every detail and
drillthrough page built from it inherited a 16:9 canvas into an app that is nowhere near
16:9 -- 20 of 38 pages. Fixed 24/10/2026; check a new page's canvas if scrolling returns.

**The embed settings, both in `Web/index.html`:**
- `customLayout.displayOption: 0` = FitToPage. **FitToPage was tried and rejected once
  before** -- against the MIXED canvases, where 720 pages lost ~15% of width to bars. With
  one canvas it is a couple of percent. Do not revert it on the old verdict.
- `.embed-full` carries `aspect-ratio: 1280 / 600` behind `@supports`, so a wide display
  leaves background to the RIGHT instead of equal bars either side. The guard matters: with
  `width: auto` and no aspect-ratio support the box fit-contents around an iframe with no
  intrinsic width and collapses to ZERO -- a blank report, no error.

**Why:** both halves look like a display-setting problem and are actually a canvas problem.
An earlier fix used `max-width: calc((100vh - 100px) * 16/9)`, guessed the chrome height
short, and pushed the report off the left edge -- hence no viewport constants.

**How to apply:** new pages start at 1280x600. The 20 converted pages were SQUASHED 5/6 on
the vertical axis, not redesigned, so they are 17% shorter than drawn and want a layout pass.
Related: [[pbir-json-must-be-utf8-no-bom]], [[pbir-mobile-layout-model]].
