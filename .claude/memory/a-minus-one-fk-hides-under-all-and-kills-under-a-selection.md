---
name: a-minus-one-fk-hides-under-all-and-kills-under-a-selection
description: "When picking a filter value blanks metrics but \"All\" looks fine, suspect unresolved -1 foreign keys, not the report."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T23:28:02.776Z
---

"All sites" applies **no filter**, so rows holding the unknown key `-1` survive it. Selecting a
real value drops every one of them. So a metric that reads fine under "All" and blanks under a
selection is almost always an **unresolved FK in the fact**, not a broken visual — and the
symptom appears only for customers who actually touch the filter.

**Why:** on 2026-09-27 selecting the only site on a single-site practice blanked Diary Fill,
both revenue-per-hour metrics, Avg Plan, Exam Ratio, Book Before You Leave, Cancel %, Short
Notice and Rebooked %. Three facts had no usable site key: `Fact_Practitioner_Diaries` had no
site **column at all**, `Fact_Treatment_Plans` wrote a hardcoded `-1` on both tenants, and
`Fact_Appointments` was all `-1` on generated tenants because Dentally fills
`Practitioner_Site_ID` and the generator does not — which is why it was "worse on the demo than
on Maple". Fixed in V195 by resolving all three from the practitioner's site
(`Dim_Practitioners.Site_ID`, populated on every practitioner of both tenants), appointments
keeping their own source site via COALESCE.

**How to apply:** when a filter selection empties tiles, count `fk_* = -1` per tenant on the
facts behind them before touching any DAX — `Config.Metric_Definitions.Supports_Site` marks
which metrics are expected not to slice. Check per tenant, since one tenant resolving and
another not will average into a false pass. The same trap applies to any dimension, not just
site. Related: [[read-the-schema-before-querying-it]].
