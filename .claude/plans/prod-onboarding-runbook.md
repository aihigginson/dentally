# Prod Onboarding Runbook — Maple Dental (Tenant 100)

Fresh, from-scratch onboarding of the **real** Maple Dental data into the **prod** Fabric
workspace, then flip to nightly deltas. Dev and prod are **separate Fabric workspaces**, so
everything (warehouse code, notebooks, token, config) must exist in prod independently.

> **ONE OPEN BLOCKER — `treatment_plan_items` 413.** Do not start Phase 1 until the tpi 413 is
> characterised (run `API/dentally_probe_413.py` after the rate budget resets) and the targeted
> fix is shipped. A fresh full tpi pull will otherwise die partway (~106k rows) and you'll get an
> *incomplete* clinical-financial layer with no error to tell you it's short. Everything below is
> ready; this is the only gate.

---

## Phase 0 — Prerequisites (all must be green before Phase 1)

- [ ] **tpi 413 fix shipped** (see blocker above).
- [ ] **Warehouse code deployed to prod** — GitHub *Deploy Warehouse* action (OIDC), latest
      manifest through **V046**. Confirm `Migrate.Deploy_Log` in the prod warehouse shows V042–V046.
- [ ] **Notebooks imported to the prod workspace**, each repointed at the **prod** LH/WH:
      `Ingest_Dentally`, `Orchestrate_Build`, `Freeze_Onboarding_Stage`.
- [ ] **Real token in prod Key Vault** — Maple's Dentally token in `kv-analytically` secret
      `dentally-tokens-prod` (per-env pattern, mirrors `xero-tokens-<env>`). The ingest is
      **token-driven**: the tenant it pulls is the one whose token is present.
- [ ] **T100 configured in the prod warehouse** — a row in `Audit.Tenants` and the relevant
      `Audit.Environment_Config` mappings (workspace / lakehouse / warehouse) pointing at prod.
- [ ] **`Gold.Load_Watermark` empty** in prod (fresh install → nothing to reset; if T100 was ever
      partially loaded in prod, `TRUNCATE Gold.Load_Watermark` so the watermark facts full-load).
- [ ] **Security.Application_Users** has the Maple UPN(s) → Client → Tenant 100 mapping in prod
      (the app's RLS + practitioner-filter gate reads this).

---

## Phase 1 — Full pull to Stage

Run **`Orchestrate_Build`** in the prod workspace with:
- `run_dentally_ingest = True`
- `full_refresh = True`  ← the full onboarding pull (`updated_after` unset; history floor applies
  to `treatment_plans` / `treatment_plan_items` per `HISTORY_FLOOR_ENTITIES`)
- tenant scope = T100 (token-driven; confirm no other real token is present)

This lands `stage_*` (overwrite-per-tenant). Long + rate-limited (3600 req/clock-hour, `per_page`
100). Resume-safe if it stalls on the hour boundary. `patient_stats` runs its post-loop
bulk→dedup→gap-fill (option B); `recalls`/`tpi` twins are killed by the general within-entity dedup.

**Decide the history floor for prod first.** Maple's migration landed ~2020; we used **2021-01-01**
in dev. Confirm the same (or tighter) floor is set for the prod run — migrations land at different
dates for different customers, so this is a per-customer decision, not a constant.

---

## Phase 2 — Validate Stage (before building anything)

1. **Dup / gap check** — run `Fabric/Check_Stage_Duplicates.sql` against the prod stage.
   **Empty result = clean.** (Excludes `patient_stats` + `Practitioner_Diary_Breaks` by design.)
2. **Row-count sanity** — spot-check the big entities' stage counts against Dentally
   `meta.total_count` for the same floor/window (catches a silent pure-gap pull with no dups).
   Especially `treatment_plan_items` and `treatment_appointments` — the two that stress pagination.
3. Only proceed once stage looks right. Stage is the cheap-to-inspect, expensive-to-re-pull layer.

---

## Phase 3 — Build Bronze → Gold

Run **`Orchestrate_Build`** build-only (`run_dentally_ingest = False`) for T100. Canonical
Bronze → Silver → Gold → aggregate DAG. Watermark facts full-load because `Gold.Load_Watermark`
is empty (Phase 0). Silver/Dim reporting "0 processed" is normal (hash-gated, first load still
inserts; only Bronze always reports counts).

---

## Phase 4 — Validate the warehouse

- [ ] No failed steps in `Audit.Process_Execution_Log` for the run.
- [ ] Spot-check Gold row counts (Dim_Patients has **no** dup `bk` — the patient_stats bug's tell),
      `Fact_Invoice_Items` non-empty (so `Fact_Metric_Actuals.fk_Date` isn't NULL), working-hours
      chain populated (V046 — Chair Utilisation / Rev-per-Clinical-Hour not blank).
- [ ] Model refresh succeeds (the `_Treatment Plans[fk Treatment Plan]` dup that broke refresh in
      dev was the patient_stats cascade — should be clean here).

---

## Phase 5 — Repoint prod semantic model + PBI

- [ ] Point the **prod** semantic model at the **prod** warehouse (it currently references dev —
      this is the open "repoint prod off dev" item; loading prod data first was the precondition,
      now met).
- [ ] Re-add the service principal as **Member** of the prod workspace if it changed (effective
      identity handles RLS, not PBI Service assignments).
- [ ] Confirm the app's report embeds + filter bar resolve T100 under RLS (Maple UPN → Tenant 100).

---

## Phase 6 — Freeze the onboarding stage

Run **`Freeze_Onboarding_Stage`** (prod), `tenant_id="100"`, `direction="freeze"`.
`stage_*` → `init_stage_*` in prod `LH_Dentally`. This is the safety net: after it, a delta may
overwrite `stage_*` without losing the (expensive, rate-limited, sometimes un-re-pullable)
onboarding snapshot. To rebuild later without re-pulling: `direction="restore"` then Phase 3.

---

## Phase 7 — Switch to nightly delta

- Schedule **`Orchestrate_Build`** with `run_dentally_ingest = True`, `full_refresh = False`.
  Delta = `updated_after` since last run; Bronze MERGEs onto history; watermark facts advance
  their cursor from `Gold.Load_Watermark`.
- **Known delta exceptions (not blockers for onboarding, but for the delta phase):**
  - `patient_stats` — no working `updated_after`; option B full-pulls + gap-fills every run (done).
  - `recalls` — pagination bug **and** regularly deleted; delta-upsert can't remove deletes →
    needs **full-refresh-every-run** (pull-all + overwrite, ideally per-patient
    `GET /patients/{id}/recalls`). Fix still pending — safe at onboarding (full pull), address
    before relying on delta recall accuracy.

---

## Notes / decisions baked in
- Frozen area = **`init_stage_*` in the same `LH_Dentally`** (not a separate lakehouse) — no new
  infra, same-lakehouse Spark copy.
- **T11/T12 never enter the delta space** — they're seed→build-only synthetic tenants.
- `usp_Clear_Tenant_Data` (data-only tenant clear, preserves Audit/Security/Config/Test) is part of
  the fuller onboarding architecture but **not required for a fresh prod install** (nothing to
  clear). It's needed for a *re-onboard*.
