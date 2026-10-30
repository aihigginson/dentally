---
name: generator-column-set-is-the-dev-stage-schema
description: "seed_onelake overwrites the Delta schema, so any column the generator omits ceases to exist on DEV -- breaking SELECT * Stage views and Bronze loaders at once."
metadata:
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-28T11:25:35.934Z
---

`seed_onelake.write_stage` writes every table with `mode="overwrite", schema_mode="overwrite"`
(V011 data minimisation — dropped columns are *meant* to disappear rather than linger as nulls).
So **the synthetic generator's column set is the DEV Stage schema.** Whatever no tenant emits
does not exist there, however faithfully Bronze asks for it.

The trap: some columns reached DEV Stage only as a **side effect of the real API ingest** landing
the full Dentally field set. Synthetic rows simply read NULL in them because Delta had unioned the
columns in. Seed the synthetic tenants alone and those columns are gone — and two things break,
neither naming the cause:

* **Stage views are `SELECT * FROM LH_Dentally.dbo.stage_*`**, and SQL Server binds the column
  list at CREATE time. A lost base column makes every read fail with *"View or function
  'Stage.X' has more column names specified than columns defined"* — which reads like a wrong
  hand-written column list, and there isn't one. Fix: re-run `Fabric/Stage.Views.sql`
  (34 idempotent DROP/CREATE pairs), but **only after** the base table has its columns back,
  or you just bind the short list.
* the Bronze loader naming the column fails on an invalid column name.

**A loader-side fallback does NOT save it.** `COALESCE([day],[date])` and
`COALESCE(NULLIF(TRIM(Practitioner_Site_ID),''), dpr.Site_ID)` rescue a NULL *value*, never an
absent *column*. Such a column must be present and NULL.

Fixed 2026-10-28 (commit 5f44cf1): `generate_tenant` now emits `practitioner_site_id` +
`updated_at` (appointments), `day` + `unavailable` (diary entries), `reminders` (recalls), all
NULL — restoring the schema without moving a downstream number.
`Web/tests/test_generator_covers_bronze.py` fails if any Bronze loader selects a column no
tenant produces. **Always verify such a guard by deleting each column in turn** — the first
version passed with all five missing, because subtracting output aliases
(`LEFT(reminders,8000) AS Reminders`) deleted the source columns too.

## After a reseed that CHANGES a column set, do these in order

The lakehouse **SQL analytics endpoint syncs Delta schema asynchronously**, and nothing errors
while it is behind — it serves the OLD column list over the NEW parquet, so columns read as all
NULL and everything after the insertion point shifts (`tenant_id` came back 0 non-null; a
timestamp column read as `24`). It looks exactly like the seed failed to write those tables,
and the row counts proving otherwise are the tell: they matched the generator exactly.

1. `python seed_onelake.py --tenants 11,12,21,22,23,24 --env dev` (all of them — `--partial`
   guards a subset, because every write is a full overwrite).
2. **Refresh the endpoint metadata** — `POST /v1/workspaces/{ws}/sqlEndpoints/{id}/refreshMetadata?preview=true`
   (endpoint id from `GET /v1/workspaces/{ws}/lakehouses/{lh}` → `properties.sqlEndpointProperties.id`;
   DEV endpoint `e9a9352d-daa3-4767-9762-fddd51f5b0e2`). Returns 202 + a Location to poll.
   Waiting does not reliably do it; the explicit call completed in one poll.
3. **Then** re-run `Fabric/Stage.Views.sql`. Order matters both ways — rebuild the views before
   step 2 and they bind the stale short list, which is just as broken and reads as success.
4. Verify by *reading* the views, not by the CREATEs succeeding: a stale binding only shows on
   read, and a view with too FEW bound columns does not error at all, it silently hides them.

Scripts for 2 and 3 are in this session's scratchpad (`refresh_sql_endpoint_dev.py`,
`recreate_stage_views_dev.py`), both DEV-hardcoded with no env switch.

Also learned here: a trial-decode loop that tries `utf-16` first **silently mangles UTF-8** —
ASCII bytes pair into valid CJK with no NUL, so the decode "succeeds" and returns mojibake.
Decode Fabric SQL **by BOM**, and assert the result contains `SELECT`. Confirms
[[sql-files-are-mostly-utf8-not-utf16]]: `Stage.Views.sql` is plain UTF-8.

`--partial` now guards a subset seed. Related: [[batch-generator-changes-before-reseeding]],
[[demo-tenant-bronze-accumulates-every-generation]], [[read-the-schema-before-querying-it]].
