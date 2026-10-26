---
name: insight-panel-parked-for-ml
description: "The Home highlight strip was withdrawn 2026-10-25 — the DISPLAY was approved, the movement ranking was rejected; restore from dac6dab when there is a model."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-25T18:13:36.849Z
---

The six-card weekly highlight strip above the Home report was withdrawn on 2026-10-25.
Split the verdict carefully, because it is easy to get backwards:

* **The display was liked.** "I really liked the display — it was just that the headlines
  were totally meh and noise." It is not a design to redo. `git show dac6dab:Web/index.html`
  holds the markup, the `.insight*` CSS and `loadInsights()` / `_insightValue()` /
  `_insightChange()` verbatim.
* **The ranking was rejected, on concept not tuning.** It scored 4-week movement ×
  `Area_Weight`. `Area_Weight` exists for the Home page's five AREA HEADERS (see
  `Scripts/Generate_Area_Weights.py`), and 16 of the 44 active metrics carry none, so the
  loader's `ISNULL(m.Area_Weight, 5)` made every one of them eligible to headline.
* Year-on-year was removed first (V248) for the same reason: the panel reports recent
  movement, and a window from a year ago is not that. The +1052% on `lapsed_deactivated`
  was arithmetically correct off a base of 31 — last year's window went 31 → 357, a one-off
  tidy-up — so no materiality floor would have caught it. I tried one; it was the wrong fix.

What the owner wants is forward-looking and causal: "lots of cancellations, expect the
lapsed numbers to start rising"; "more forward diary slots or appointments for the
implantologist, expect a surge in revenue". That is a temporal model, not metadata —
`Config.Metric_Definitions` groups metrics by where they are DISPLAYED (`Section`) and
nothing encodes what drives what.

**Why:** declaring cause and effect by hand was considered and set aside by the owner; the
intended replacement is ML, possibly predictive, feeding the same strip.

**How to apply:** `Gold.Aggregate_Practice_Insights`, `/api/insights` and
`/api/insights/narrate` were deliberately NOT removed and still have tests — returning to
this means building a ranking, not a pipeline. Do not propose re-weighting the register as
the fix. Note also that `cancellation_rebook` ("Cancellations Rebooked") is defined but has
zero rows, and that one practice with ~2 years of history is thin for any model that has to
generalise — [[scale-target-is-100-practices]]. Related:
[[revenue-metrics-move-with-clinician-mix]], [[rank-insights-on-weighted-movement]],
[[payment-allocations-has-never-ingested]].
