---
name: revenue-metrics-move-with-clinician-mix
description: "Total Revenue, Revenue per Clinical Hour and Average Plan Value track WHO is working, not how the practice is performing."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-25T18:13:20.987Z
---

Total Revenue and Revenue per Clinical Hour are mostly a function of which clinicians
worked in the window — both spike when the implantologist does a session. Average Plan
Value behaves the same way. The owner's words: "more to do with what sort of clinician is
working".

Confirmed in the data (tenant 100, 28-day windows to 2026-10-18 vs the 28 before), on the
Average Plan Value figure that was reading +33% at practice level:

* Craig Jack — 160 plans → **139**, value £24,700 → **£53,137**
* Tessa Clarke — 68 plans → **65**, value £9,369 → **£28,021**

Bigger work on FEWER plans by two clinicians. At practice grain that reads as the practice
improving, which is the opposite of what happened to plan volume.

**Why:** a practice-grain rate can move entirely on composition while every clinician's own
rate stands still, so the headline figure answers a question nobody asked.

**How to apply:** never present a movement in these three as performance without
decomposing by practitioner first — `Gold.Fact_Metric_Actuals` carries the grain
(`fk_Practitioner <> -1`, 15 practitioners at tenant 100) and `Supports_Practitioner` on
`Config.Metric_Definitions` says which metrics have it. Related: [[insight-panel-parked-for-ml]],
[[site-keys-are-fine-metric-actuals-is-not]], [[attribute-by-line-not-by-invoice-header]].
