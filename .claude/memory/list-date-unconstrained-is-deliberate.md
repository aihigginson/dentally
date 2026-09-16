---
name: list-date-unconstrained-is-deliberate
description: List Date Unconstrained is a required second date table, not a workaround - Day Book is the one report the period filter is not forced on.
metadata:
  type: project
---

`List Date Unconstrained` (and `Aggregate Site Patient Practitioner Daily Unconstrained`)
are a deliberate second date axis, not legacy cruft. Every report has the period filter
forced onto it; **Day Book does not**, because its lists are current/forward-state
operational work -- recalls to action, open plans, cancellations and DNAs to rebook -- and
must show all outstanding items whatever period is selected. `Web/index.html`
`applyFilters()` encodes this as `if (periodFilter && r._section !== 'day_book')`.

**Why:** it looks removable. The Day Book's forward-looking visuals all filter on
`List Date Unconstrained[Relative Day]` rather than `List Date`, which reads like someone
dodging a bug -- and on 2026-09-16, having just fixed an unrelated RLS defect that also hid
future dates, I suggested it might now be redundant. It is not: the two tables answer to
different filter regimes, and collapsing them would drag the period filter onto Day Book.

**How to apply:** treat the split as load-bearing. Before proposing that a second date
table, aggregate, or "Unconstrained" variant be merged away, work out which filter it is
built to escape. See [[rls-m2m-truncates-list-date]].
