---
name: a-role-filter-blanks-on-my-data
description: "My Data is filtered to the signed-in practitioner, so any measure that forces List Practitioners[Role] returns blank on that person's own page."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-06T14:27:54.713Z
---

`Web/index.html` applies `List Practitioners[Full Name] In [<the user's own name>]` to My Data
(`selectMyDataPractitioner()`; locked for the `clinician` profile, defaulted-but-changeable for
full access). So **a measure that also filters `[Role]` intersects two filters on the same table and
returns blank** on the page it was built for.

Cost two round trips on the hygienist cross-charge: `Cross-Charge to Hygienists` and
`Plan Hygiene Visits` both forced `Role = "Hygienist"`, and Craig — the only person who was going to
look at the page — is a Dentist. As him: `[Plan Members]` 469, `[Plan Capitation Fee]` 810,882,
both role-forced measures **blank**.

**How to apply:** on a My Data visual, never filter the practitioner table. Find the discriminator
in the fact instead. For the cross-charge the **sign of the leg** carries the side — negative is the
dentist's debit, positive is the hygienist's credit — so `Cross-Charge Out` / `Cross-Charge In` read
correctly for a dentist, a hygienist, and the whole practice at once. Same for counting: count
patient-and-date over the pair, not role-filtered appointments.

Related: [[my-data-is-unfiltered-for-vendor-accounts-by-design]] (the vendor case is the opposite —
no practitioner linked, so nothing is filtered), [[a-minus-one-fk-hides-under-all-and-kills-under-a-selection]].
