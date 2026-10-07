---
name: publishing-from-desktop-overwrites-a-service-refresh
description: A .pbix publish replaces the dataset's data; service-side refreshes are lost.
metadata:
  type: reference
---

`PBI Dentally` is an **Import** model. Publishing from Power BI Desktop uploads the data cached
inside the .pbix, replacing what the service holds — so a refresh triggered in the service (or
by API) survives only until the next publish.

**Why it bites here:** warehouse data changes constantly (nightly builds, demo re-seeds), while
the .pbix on the laptop holds whatever was imported when it was last opened. Publish a DAX or
RLS fix and the model silently reverts to week-old data. On 2026-09-26 the demo practice read
blank for nearly every metric for exactly this reason — the data tables were last refreshed
19 September, before the demo tenant had any data, while `Application Users` (the table just
edited) showed that day's timestamp. The give-away is per-table `RefreshedTime` disagreeing:

```
pwsh -File Scripts/Check_RLS_Expression.ps1     # TOM connection pattern to copy
# $db.Model.Tables[..].Partitions[..].RefreshedTime
```

**How to apply:** refresh in Desktop BEFORE publishing, or push metadata only (Tabular Editor
"deploy metadata only", or TOM over XMLA) so the service keeps its own data. Before concluding
that RLS or a filter is broken, check the partition refresh times — stale data and a broken
rule look identical from the report. See [[rls-m2m-truncates-list-date]].
