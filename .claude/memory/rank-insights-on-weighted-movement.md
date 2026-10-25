---
name: rank-insights-on-weighted-movement
description: "Practice insights rank on 4-week movement x Area_Weight, never on distance from target."
metadata:
  type: project
---

`Gold.Aggregate_Practice_Insights` (V227) picks the three metrics getting worse and the
three getting better, per tenant, nightly. Three design choices, each measured on the
live tenant rather than reasoned about:

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

**How to apply:** do not "improve" this by reintroducing distance-from-target ranking or
a shorter window; both were tried and rejected on evidence. Narrative text is written by
a language model afterwards and is NULLABLE -- the ranking must stand alone when the
model is slow, unavailable or off. Related: [[the-demos-bad-numbers-are-the-pitch]],
[[capitation-is-an-estimate-not-observed-income]].
