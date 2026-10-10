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

## 2026-10-09: and the automatic refresh that follows a publish may do NOTHING

The build's refresh step reported `Completed` on all 57 objects **in 14 seconds** and loaded none
of them. The model kept pre-reseed data for an hour while the API insisted it had refreshed; the
demo tenant's Capitation tab showed plan names that no longer existed.

**14 seconds is the tell.** Prod's nightly build-triggered refresh runs 4-13s and IS current
(checked against the warehouse the same day: Inactive Plan Patients 58, Possibly Incorrectly
Allocated 7, matching exactly). So a fast refresh is normal. What is NOT normal is a fast refresh
on a model that was republished from Desktop a few hours earlier.

**How to apply:** after ANY Desktop publish, trigger a **Full** refresh explicitly and wait for it.
Do not trust the build's automatic one to repopulate a freshly-published model.

```powershell
# type:Full, not Automatic -- Automatic reported success and loaded nothing
POST .../datasets/{id}/refreshes  '{"type":"Full","commitMode":"Transactional","maxParallelism":4}'
```

**And verify by asking the model, not the API.** A refresh status is not evidence. One bounded DAX
query against `executeQueries` settles it in seconds and costs nothing worth worrying about:

```
EVALUATE CALCULATETABLE(SUMMARIZE('List Payment Plans','List Payment Plans'[Payment Plan Name]),
                        'List Payment Plans'[Tenant ID]=11)
```

Two false conclusions were drawn before this one: that it was browser cache (incognito appeared to
fix it, and had not), and that the app's one-hour `_REPORT_META_TTL` was to blame (it is
server-side, so incognito would never have touched it).
