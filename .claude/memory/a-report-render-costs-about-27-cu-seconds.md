---
name: a-report-render-costs-about-27-cu-seconds
description: "Measured from the 2026-10-02 break test - one embedded report render costs ~27 CU-s, so an F4 carries ~44 page loads per 5-minute interactive window."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-02T08:41:45.640Z
---

Derived from the break test, not estimated. The test pinned the one number everything else follows
from.

        F4 capacity                      4 CU
        interactive smoothing window     300 s
        budget per window                1,200 CU-s
        renders to exhaust it            40-50   (4-5 "act as" switches x 10 renders)
        ==> COST PER REPORT RENDER       ~27 CU-s  (24-30)

**Headroom on an F4, with the preload off (1 render per page load):**

        ~44 page loads per 5-minute window
        10 simultaneous logins  = 270 CU-s = 22% of budget, 4.4x headroom
        same 10 with preload ON = 2,700 CU-s = 225%          throttles immediately

So the answer to "does an F4 support 10 simultaneous users" is **yes, now** — and it was **no**
before [[act-as-reloads-and-re-embeds-ten-reports]] was fixed. The owner's hope was not
over-optimistic; the preload was eating the entire margin.

**Why this supersedes an earlier figure:** a prior estimate of ~160 CU-s per render was circulating
in this project. It is wrong by about 6x. At 160, a single switch (1,600 CU-s) would have broken a
1,200 CU-s budget — but it measurably took 4 to 5. The self-check that the arithmetic is right:
1,200 / 27 / 10 = 4.4 page loads to break with the preload on, against 4-5 measured.

**How to apply:** this counts RENDERS (a page load, or opening an unvisited section). It does NOT
cost ongoing interaction — slicer clicks, drill-through, filter changes all fire DAX and were never
measured — so treat 44/window as a page-load ceiling, not a user-activity ceiling, and keep real
headroom above it. At 100 practices the average is trivial (~2 renders per window, ~5% of budget);
the binding constraint is the CORRELATED MORNING LOGIN. A 25%-of-daily-logins burst in one window
needs F8, and F16 puts it at 28%. Related: [[scale-target-is-100-practices]],
[[how-to-bounce-the-fabric-capacity]].
