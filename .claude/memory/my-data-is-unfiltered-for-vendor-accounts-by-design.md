---
name: my-data-is-unfiltered-for-vendor-accounts-by-design
description: "My Data has three intended tiers - vendor accounts get the aggregate for bug reproduction, full-profile practice users default to themselves but can switch for performance reviews, and clinicians are locked."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-02T09:25:11.788Z
---

`Security.Application_Users.Practitioner_Full_Name` is the single field that decides this. All
three behaviours are INTENDED; none is a defect to chase.

| account                          | practitioner | My Data opens on   | slicer |
|----------------------------------|--------------|--------------------|--------|
| `admin@`, `grace@` (Analytically)| NULL         | practice aggregate | free   |
| Craig, Stephen, Lindsey (`full`) | linked       | themselves         | free   |
| David Mason (`clinician`)        | linked       | themselves         | LOCKED |

- **Vendor, NULL:** `selectMyDataPractitioner()` has no name to select, so it opens on the
  aggregate and the slicer stays usable. Deliberate — Analytically must be able to drill to any
  practitioner to reproduce a bug a practice reports.
- **`full` + linked:** defaults to themselves, can re-select. Deliberate — Craig runs performance
  reviews from this tab.
- **`clinician`:** `myDataLock` is true only when My Data is the user's SOLE report, which disables
  the slicer.

**Verified 2026-10-02** by temporarily setting `admin@`'s `Practitioner_Full_Name` to 'Craig Jack'
(identical profile, same 9 modules, so an exact reproduction) — it defaulted to Craig as expected,
then was restored to NULL.

Note for reference, not as a concern the owner has not already weighed: the practitioner scoping is
a slicer default plus a disabled `<select>`. The embed token carries TENANT scope only
(`username` + `customData`) and no RLS expression in the model references a practitioner. Proposals
to gate the NULL case or add practitioner-level RLS were both declined on 2026-10-02.

**How to apply:** if My Data looks wrong, check `Practitioner_Full_Name` FIRST — it explains every
variant above. Do not propose RLS changes for it. Related:
[[support-logins-are-not-dentally-users]], [[dont-re-raise-settled-decisions]].
