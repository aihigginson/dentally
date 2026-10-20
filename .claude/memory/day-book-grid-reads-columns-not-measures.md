---
name: day-book-grid-reads-columns-not-measures
description: "The Day Book summary grid binds to stored COLUMNS on List Practitioners, not the DAX measures of the same name."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-20T13:22:53.082Z
---

The Day Book summary grid (`Recalls To Action`, `Cancellations To Rebook`,
`DNAs To Rebook`, `Open Plans`, `Days Until Next 30 Free`) binds to **columns on
`List Practitioners`**, not to the identically-named measures in `_Measures`.

Those columns are `Gold.Aggregate_Site_Practitioner_Current.*`, built in
`usp_Load_Aggregate_Site_Practitioner_Current` from `#op` / `#cx` / `#dn` / `#rc`, each
joined to `Gold.vw_Effectively_Active_Patients` and split by the fact's own
`fk_Practice_Site`.

**Why this costs time:** a same-named DAX measure exists in `_Measures` for several of
them. Editing it changes nothing on the grid and the model still reports the edit applied,
so it reads like a failed deployment. 2026-10-20 that cost a full round of "the fix hasn't
worked", a wrong accusation that the csx had not been saved, and an argument with the owner
who could see the new DAX in Tabular Editor and was right.

**The tell:** open the visual.json and look at whether the field is `"Column"` or
`"Measure"`, and which `Entity` it resolves to. `Column ... <- List Practitioners` means
the number is precomputed in SQL and only a warehouse release can change it.

**Three definitions of the same number existed** for recalls, and changing one never moves
the others:

| surface | where | active-patient test |
|---|---|---|
| summary grid | `#rc` in the agg proc | `vw_Effectively_Active_Patients` |
| `_Measures` DAX | `PBI_Dentally.csx` | none |
| Recall Details drill | report filters | `List Patients[Effectively Active]` |

Changing the grid means changing the detail page too or the drill stops reconciling to the
tile. See [[a-detail-table-needs-a-column-not-a-measure]] and
[[two-open-course-no-appt-figures-disagree]] -- same family: one number, several homes.
