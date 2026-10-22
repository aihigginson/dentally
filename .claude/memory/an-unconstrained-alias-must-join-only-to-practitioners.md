---
name: an-unconstrained-alias-must-join-only-to-practitioners
description: "An imported _<Fact> Unconstrained alias auto-detects joins to shared dims, creating two paths to the same table -- which breaks pages that never referenced it."
metadata:
  type: project
---

Importing `_Treatment Plans Unconstrained` let Power BI auto-detect relationships. It picked
up `List Patients` and `List Treatment Plans` alongside the practitioner join that was
actually wanted. Both of those dims are already joined to `_Treatment Plans`, so the model
then held two paths from `_Treatment Plans` to `List Patients`:

    _Treatment Plans -> List Patients
    _Treatment Plans -> List Treatment Plans -> _Treatment Plans Unconstrained -> List Patients

**The symptom is not on the page you changed.** The Clinical spider rendered fine; the HOME
page died with `Join paths are expected to form a tree`. Every visual whose query can touch
both tables fails, so the blast radius is the whole model, not the new feature.

**It happened twice in one session.** The second was a relationship to `List Date`, and that
one is worse because nothing errors: the app's "Last 12 Months" simply reached the alias and
every plan spoke on the radar silently became a 12-month slice of a 24-month cohort. Mark's
Y1 Avg read 327 against a true 447, %Proposed 74.6 against 82.1.

**How it was caught:** %Attrition matched the warehouse exactly while all four plan spokes
were off. That split is the tell -- the patient measure has no date relationship and the plan
measures do. Re-deriving in SQL with a 12-month filter added reproduced the chart to the
decimal, which named the cause rather than guessing at it.

Fix: deactivate the alias's joins to everything except `List Practitioners`. The measures on
an Unconstrained alias filter only its OWN columns by design (that is the entire point of the
alias -- the report's date slicer must not reach it), so it needs no dimension beyond the one
it is sliced by.

**Why:** the alias exists to be isolated. Any join into the shared dimension chain both
re-exposes it to report filters and risks this ambiguity, and the error surfaces somewhere
unrelated hours later.

**How to apply:** after importing any `_<Fact> Unconstrained` or `List <Dim> Unconstrained`
table, open the model diagram before publishing and delete every auto-detected relationship
you did not ask for -- to List Date above all. Then check a figure against SQL before
believing the chart. Related: [[list-date-unconstrained-is-deliberate]],
[[a-new-model-table-has-no-rls]], [[get-data-bakes-a-literal-endpoint-into-the-model]].
