# Releases (manifest-driven deployment)

A release is an **ordered manifest** of warehouse actions, applied by the single
standard runner `Scripts/Deploy.ps1`. This replaces the bespoke per-change
`Scripts/Deploy_*.ps1` scripts: the *what-and-in-what-order* now lives in a
versioned, reviewable file that ships **with** the release, and the runner is
generic.

```
.\Scripts\Deploy.ps1 -Manifest Releases\V001__patient_cohorts.manifest          # apply
.\Scripts\Deploy.ps1 -Manifest Releases\V001__patient_cohorts.manifest -WhatIf  # list, run nothing
```

`Deploy.ps1` authenticates as the Test Runner service principal (AAD token + .NET
SqlClient, same creds as `Run_Tests.ps1`/`Migrate.ps1`) so it runs locally and in
CI unchanged, no interactive sign-in.

## Manifest format

One action per line. Blank lines and `#` comments are ignored. First token is the
**tag**, the remainder is the **argument**.

| Tag | Meaning | Argument | Idempotency |
|---|---|---|---|
| `MIGRATE` | Apply a tracked, once-only schema delta. **Load** a table change. | path to `Migrations\Vnnn__*.sql` | Recorded in `Migrate.Schema_Version`; **skipped** if already applied |
| `DEPLOY` | Execute a SQL object file (split on `GO`). **Load** a proc/view/function or seed. | path to `Fabric\*.sql` | DROP/CREATE (or TRUNCATE+INSERT) -- safe to re-run every release |
| `EXEC` | Run an inline T-SQL batch. **Run** a proc / reload / backfill / view regen. | the T-SQL (rest of line) | As idempotent as the SQL you write (declare OUT params inline) |
| `TEST` | Run the `Run_Tests.ps1` regression + reconcile + RLS gate. | *(none)* | Read-only gate; fails the deploy on a test failure. No `-Promote` (promotion stays a human step). |

The `DEPLOY` vs `EXEC` split is the key distinction: **`DEPLOY` loads** a stored
procedure (creates the object); **`EXEC` runs** one (executes it).

Example:

```
MIGRATE  Migrations\V001__patient_cohort_flags.sql
DEPLOY   Fabric\Gold.usp_Load_Dim_Patients.StoredProcedure.sql
EXEC     DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Gold.usp_Load_Dim_Patients @Mode='PROD',@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
EXEC     EXEC Meta.usp_Create_Gold_Views;
TEST
```

## Conventions

- **Naming:** `Releases\Vnnn__<snake_description>.manifest`, sequential. (The release
  number is its own sequence -- independent of the `Migrations/Vnnn` numbers it
  references by path.)
- **Order matters and is explicit.** The canonical order is: schema deltas
  (`MIGRATE`) -> object (re)deploys (`DEPLOY`) -> data moves / reloads / view regen
  (`EXEC`) -> verification (`TEST`). See `Migrations/README.md` for the why.
- **Forward-only.** Migrations don't roll back; a bad release is fixed by a new
  forward migration/release. `TEST` runs *after* the changes (it validates the new
  state), so a failed gate means roll forward with a fix.
- **ASCII-only**, like all PowerShell-read files here (PS 5.1 reads as CP1252).

## Writing a new release

1. Add any schema deltas as `Migrations/Vnnn__*.sql` (ALTER, guarded). Keep the
   matching `Fabric/*.Table.sql` fresh-install definition in sync by hand.
2. Edit/add the `Fabric/*.sql` objects (procs, views, seeds).
3. Write `Releases/Vnnn__<name>.manifest` listing the steps in order.
4. `Deploy.ps1 -WhatIf` to review, then run it against dev.
5. Commit manifest + migration + objects together -- the manifest is the release.

## CI

`.github/workflows/deploy-warehouse.yml` runs a manifest via `Deploy.ps1` (as the
SP, using the `FABRIC_SP_*` repo secrets), then runs the `dw-tests` gate to verify.
Triggered by **workflow_dispatch** with the manifest filename as input -- a
deliberate, controlled release rather than an implicit push deploy.

> `Scripts/Migrate.ps1` still exists as a dev convenience (auto-discovers and
> applies *all* pending migrations); the manifest's `MIGRATE` tag shares the same
> `Migrate.Schema_Version` tracking, so the two never double-apply.
