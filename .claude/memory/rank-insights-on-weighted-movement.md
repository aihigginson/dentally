---
name: rank-insights-on-weighted-movement
description: "SUPERSEDED 2026-10-25 -- the movement ranking was rejected outright; kept only for what was already ruled out."
metadata:
  type: project
---

==> THE RANKING THIS DESCRIBES WAS REJECTED BY THE OWNER ON 2026-10-25. <== Not retuned --
rejected on concept, and the display withdrawn with it. See [[insight-panel-parked-for-ml]]
first; the short version is that `Area_Weight` exists for the Home AREA HEADERS and 16 of
the 44 active metrics carry none, and a practice-grain rate move can be pure clinician mix
([[revenue-metrics-move-with-clinician-mix]]).

This note is kept ONLY for the alternatives already ruled out, so they are not re-proposed
as the fix. The year-on-year comparator described below was removed entirely in V248.

`Gold.Aggregate_Practice_Insights` (V227) picked the three metrics getting worse and the
three getting better, per tenant. Three design choices, each measured on the live tenant
rather than reasoned about:

**Distance from target is the wrong ranking.** It returned Outstanding Invoices, Open
Courses Value and Open Courses -- enormous multiples of target, all already known, all
confirmed as WIP that is correctly high. Distance measures how long a problem has
existed. Movement measures whether to act today.

**Four weeks against four weeks, stepped weekly.** Months are unequal lengths (a count
falls every February). Week-on-week is noise: Deposit Ratio read 4.0 / 6.8 / 12.5 /
11.9 / 30.9 / 9.9%, flipping verdict on consecutive weeks. Four-against-four gave the
same verdict four runs running for both Short Notice Cancellations and Average Plan
Value.

**`Config.Metric_Definitions.Area_Weight` decides, not the percentage**, with movement
capped at 100% so a small denominator cannot buy the top slot. Total Revenue is 45 and
Revenue per Clinical Hour 40, against Email Details 8 and Deposit Ratio 5.

Counts normalise per working day (a bank holiday is not a 20% collapse); rates do not,
since a rate divides its own denominator out. Only complete weeks compare.

**Why:** the owner's framing -- "a slight downwards move in revenue is more important
than a seismic change in email details" -- is already encoded in Area_Weight, and the
noise and seasonality traps are real and were both hit in prototypes before being fixed.

**How to apply:** do not "improve" the panel by reintroducing distance-from-target
ranking or a shorter window -- both were tried and rejected on evidence -- and do not
propose re-weighting the register either, which is where this approach ended. Narrative text is written by
a language model afterwards and is NULLABLE -- the ranking must stand alone when the
model is slow, unavailable or off. Related: [[the-demos-bad-numbers-are-the-pitch]],
[[capitation-is-an-estimate-not-observed-income]].
