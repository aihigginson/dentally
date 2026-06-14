# Database migrations

A structured, ordered, tracked alternative to the ad-hoc `Scripts/Deploy_*.ps1`
scripts (see EVALUATION.md — "Database release engineering"). Piloted with
`V001__patient_cohort_flags.sql`.

## How it works

- Each change that **alters existing state** (schema deltas, data backfills) is a
  forward-only file here named `V<NNN>__<snake_description>.sql` (`NNN` zero-padded,
  sequential — `V001`, `V002`, …).
- `Scripts/Migrate.ps1` applies all **pending** migrations in version order,
  exactly once each, recording them in the **`Migrate.Schema_Version`** table
  (version, name, SHA-256 checksum, applied-at, success). Re-running is safe — it
  skips already-applied versions. Authenticates as the Test Runner SP (same creds
  as `Run_Tests.ps1`); no interactive login.
- Migrations should be **idempotent where practical** (guard `ALTER`/`INSERT` with
  `IF NOT EXISTS`) so a partial/failed run can be retried.

## Migrations vs object scripts (the split)

| Kind | Where | How it deploys |
|---|---|---|
| Tables (schema deltas) | `Migrations/Vnnn__*.sql` (`ALTER`) | `Migrate.ps1`, once, in order |
| Stored procs / views / functions | `Fabric/*.sql` (DROP/CREATE) | re-deployed every release (idempotent) |
| Re-seedable config/data | `Fabric/*.Data.sql` (TRUNCATE+INSERT) | re-deployed every release (idempotent) |

**Why the split:** the `Fabric/Gold.*.Table.sql` files are DROP/CREATE, which would
*wipe data* on an existing warehouse. Migrations make table changes additively
(`ALTER TABLE ADD`). Procs/views/seeds are already idempotent, so they don't need
versioning — they just redeploy.

> Current limitation (v1): the table object files (`Fabric/Gold.*.Table.sql`) are the
> *fresh-install / target* definition; migrations bring *existing* DBs to that state.
> Both must be kept in sync by hand. A future improvement is a state-based diff
> (e.g. SqlPackage/DACPAC) to generate migrations from the target definition.

## Release workflow

1. **`Scripts/Migrate.ps1`** — apply pending schema/data migrations.
2. **Deploy changed object scripts** (procs, views, seeds) from `Fabric/` — idempotent.
3. **Reload Gold** (`Audit.usp_Load_All`, dims-before-facts) so new columns backfill
   and FKs re-resolve.
4. **`Meta.usp_Create_Gold_Views`** — regenerate the PBI views (metadata-driven, so
   new columns appear automatically).
5. **Refresh the PBI dataset**; run any new Tabular Editor measure scripts.
6. **`Scripts/Run_Tests.ps1`** — regression + integrity + RLS gates; `-Promote` once
   the variances are reviewed and accepted.

## Writing a new migration

```
Migrations/V002__add_widget_flag.sql
```
- Forward-only, ordered, idempotent. One logical change per file.
- Schema/data deltas only — don't put proc/view bodies here (those live in `Fabric/`).
- Test on dev first; `Migrate.ps1 -WhatIf` lists what would run.
