---
name: recalls-to-action-lives-in-three-places
description: The Day Book worklist rule is duplicated in an aggregate column, a DAX measure AND the detail page's own filters — fix all three or the summary and detail disagree.
metadata:
  type: project
---

"Recalls To Action" is defined **three times**, and they drift:

1. **`Gold.Aggregate_Site_Practitioner_Current.Recalls_To_Action`** — the `#rc` block in its
   loader. This is what the Day Book **summary grid** binds, via the `Recalls To Action`
   COLUMN on `PBI.List Practitioners` ([[day-book-grid-reads-columns-not-measures]]).
2. **The `Recalls To Action` DAX measure** on `_Measures` / "Scheduling KPIs" in
   `Fabric/PBI_Dentally.csx`.
3. **The Day Book "Recall Details" page's own hand-made visual filters** — on BOTH visuals,
   the card (Recall Count / Recall Patients) and the table. Page
   `ef8a188f262b1ccde385`, visuals `963dc2300a37e3aed83d` and `d445bd8beb27d2060e3b`.

The rule in all three: `Retention Outlook In Scope = 1`, `Is Booked = false`,
`Has Attended Since Due = false`, `Status NOT IN (Completed, Booked)` — plus
`List Patients.Effectively Active = true` in (1) and (3), which (2) does not have, so the
measure legitimately returns a larger number than the grid.

**Why:** on 2026-10-26 V249 fixed (1) and (2) and missed (3), so the summary read 155 for
David Mason and the detail page he drilled into read 182. The csx comment says "Each matches
its Day Book detail-page filter" in as many words, and I read it without following it through.

**How to apply:** changing what counts as actionable means editing all three, in the same
change. Verify by replicating the filter set in SQL against `Gold.Fact_Recalls` joined to
`Gold.vw_Effectively_Active_Patients` and checking it equals the aggregate column per
practitioner — on 26/10 that gave 155/155, 163/163, 139/139. And remember the detail-page
filters are a REPORT change: the report must be republished, a model refresh will not move
them. The same shape applies to the other Day Book detail pages (Open Plans, Cancellations,
DNAs), which carry their own filters too. Related:
[[dentally-first-reminder-is-really-the-latest]], [[a-table-projection-takes-no-displayname]],
[[changing-a-fact-means-sweeping-its-derivations]].
