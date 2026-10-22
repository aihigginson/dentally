---
name: addmeasure-on-an-existing-name-silently-loses
description: "In Tabular Editor, AddMeasure on a name that already exists keeps the ORIGINAL definition -- an edited measure then never takes, with no error."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-22T18:42:50.505Z
---

`PBI_Dentally.csx` creates measures with `tbl.AddMeasure(name, dax)`. If a measure of that
name already exists, the original survives and the edit is lost. **No error, no warning** --
the script compiles, runs, reports success, and the measure keeps yesterday's DAX however
many times it is applied.

Every measure block therefore has to DELETE everything it creates before adding it:

    foreach (var m in Model.Tables.SelectMany(x => x.Measures)
                          .Where(m => names.Contains(m.Name)).ToList())
        m.Delete();

Two refinements learned the hard way: delete across **every table** (a measure first created
on `_Treatment Plans` survives a later block targeting `_Treatment Plans Unconstrained`), and
keep the delete list in step with the add list -- four measures were added but not listed,
and only those four were frozen.

**The signature:** some axes of a chart update and others do not, with nothing in the error
log. That split IS the diagnosis -- the ones that updated were on their delete list. The
spider block never suffered it because it deletes by `DisplayFolder`, which cannot drift out
of step with the names.

**Why:** it looks identical to the script not having run, so the instinct is to re-run it or
to suspect the DAX. Both are wrong and both waste a lot of time.

**How to apply:** after editing any measure's DAX, check the measure block deletes that exact
name before re-running. A quick read-only script that lists measure names and flags
duplicates settles it in seconds -- `Fabric/TabularEditor_Diagnose.csx`. Related:
[[a-table-projection-takes-no-displayname]], [[a-new-model-table-has-no-rls]],
[[heredocs-eat-backslashes-write-a-script-file]].
