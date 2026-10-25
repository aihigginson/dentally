---
name: the-csx-owns-only-the-measures-table
description: "PBI_Dentally.csx owns '_Measures' and nothing else -- fact tables carry hand-made measures that reports bind to, so only NAMED retirement is safe there."
metadata:
  type: project
---

The model holds **three** kinds of measure, not two:

1. On `_Measures` -- every one is created by `PBI_Dentally.csx`. Nothing is hand-authored
   there, so anything the script does not rebuild has **lost its source** and should be
   surfaced and removed.
2. On the FACT tables -- many are hand-made in Desktop and reports bind to them. `[Revenue]`
   appears on **eleven** report pages, `[Recall Patients]` on seven, `[Patient Count]` on six,
   plus Awarded, Expected, Deposits, Appointment Hours, Clinical Hours and
   Next 7 Days Utilisation.
3. Genuinely dead ones left by a retired block or a rename.

**What this cost:** a sweep of "everything this script does not rebuild", run across the whole
model on 24/10/2026, flagged 41 measures and would have deleted nine live ones. It was only
caught because the owner said "it removed 20-30 orphans" -- the COUNT was the signal.

So the csx does two different things:
- **Sweeps `_Measures` only**, naming whatever it removes in one copyable dialog.
- **Retires by name** everywhere else, via the `retiredMeasures` array at the head of the file.
  Add a name there when retiring or renaming a measure.

**Why:** "the script rebuilds every folder" reads like the script owns every measure. It does
not, and the difference is invisible until something destructive runs.

**How to apply:** before deleting any measure in bulk, grep the PBIR report definitions for
its name -- `grep -rl '"<Measure>"' PBI/*/definition/pages`. A measure bound in zero pages may
still be referenced by another measure's DAX. Related:
[[addmeasure-on-an-existing-name-silently-loses]], [[a-table-projection-takes-no-displayname]].
