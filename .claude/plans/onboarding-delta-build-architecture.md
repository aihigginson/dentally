# Onboarding / Delta build architecture

Design agreed 2026-07-07. **Supersedes** the earlier `init_stage_*` / view-repoint sketch
(see [[project_dentally_go_live]]). Build deferred until the current T100 validation wraps.

## Motivation
Today the single `Orchestrate_Build` carries full-vs-delta (`@Full_Refresh`) branching, and
`stage_*` is overwrite-per-tenant. Bronze MERGE keeps history on incrementals, but:
- a `@Full_Refresh=1` in steady state would nuke history via its anti-join, and
- the raw onboarding extract (multi-hour, rate-limited, sometimes un-re-pullable) is discarded
  the moment the first delta overwrites `stage_*`.

Split the two concerns into **two single-purpose builds** and keep a **frozen onboarding
snapshot** as a pragmatic (not guaranteed) rebuild-without-re-pull safety net.

## Rejected alternative (considered + dropped)
Freezing *pre-flatten raw shapes* (minus PII) so transform bugs could be re-fixed without a
re-pull. Dropped: every transform bug this session was a one-time "first contact with real
data" cost, the shapes are stable now, this net is pragmatic not absolute, and permanently
handling raw special-category PII isn't worth it. Freeze the **post-transform `stage_*`**
(already PII-minimised). Accepted trade-off: a future transform-logic bug would need an API
re-pull -- acceptable given the structure is now known.

## The three notebooks (one transform, separate orchestration)
1. **`Ingest_Dentally`** — the shared pull + transforms. Full or delta by param. The *only*
   copy of the flatten/normalise/PII-drop logic; both orchestrators call it. Do NOT fork it.
2. **`Orchestrate_Build`** — the nightly **delta** run *and* the canonical Bronze->Gold DAG.
   - Keep the `run_dentally_ingest` on/off toggle (on = delta ingest + build; off = build only).
   - **Strip the `@Full_Refresh` / full-release branching** -> its ingest is always delta.
   - Tenant scope = **token-driven** (tenants with a `dentally-tokens-<env>` entry) = real
     practices only. Synthetic T11/T12 have no token and are excluded automatically.
   - Reused as the build-only engine by everything else.
3. **`Orchestrate_Onboarding`** — forced single `Tenant_ID`, `source = api | frozen`:
   1. **clear tenant data** — new `Audit.usp_Clear_Tenant_Data` (data only, below),
   2. **populate stage** — `api` -> `Ingest_Dentally` **full** pull; `frozen` -> copy the
      onboarding snapshot back into `stage_*`,
   3. **build** — call `Orchestrate_Build` with `run_dentally_ingest=False` (build-only; NOT a
      delta run -- stage is already fully populated),
   4. **freeze** — copy `stage_*` -> the onboarding area. **`source=api` only**, and **after
      the build validates** (today's lesson: ingest can "succeed" with wrong data; don't freeze
      until Gold looks right). Gate via a flag / final step, not blindly at end of pull.

   `source=frozen` is the **restore** path (rare; may never fire) -- same clear + build bookends
   as onboarding, differing only in how stage is populated. One dual-purpose notebook, biased to
   the 99% `api` case.

## New SQL: `Audit.usp_Clear_Tenant_Data`
`usp_Delete_All_Tenant` is too strong for onboarding-clear -- it also removes the tenant's
identity/config. Split:
- **`Audit.usp_Clear_Tenant_Data @Tenant_ID`** — deletes only the medallion **rows**:
  `Bronze.*`, `Silver.*`, per-tenant `Gold.Dim_*/Fact_*/Aggregate_*` `WHERE Tenant_ID=@X`.
  **Preserves** `Audit.Tenants` (registration + Dentally/KV mapping), `Audit.Process_Execution_Log`
  / `Process_Config` / `Process_Dependency`, `Security.Clients`/`Application_Users`, `Config.*`,
  `Silver.Appointment_Reason_Map`, `Test.*` baselines.
- **`Audit.usp_Delete_All_Tenant`** refactors to = `usp_Clear_Tenant_Data` **+** the metadata
  deletes (Audit.Tenants etc.). One data-clear list, two callers, no drift.

Side benefit: **pre-clear + plain upsert replaces `@Full_Refresh`'s anti-join** -- the clean-slate
result full-refresh gave, without any full-vs-delta branching in the load SPs. The clear *replaces*
full-refresh rather than sitting beside it.

## Storage: frozen onboarding area
Default: a **separate `LH_Dentally_Onboarding` lakehouse** (clean isolation; can be locked down /
retained independently; the immutable snapshot never mingles with the churning `stage_*`). Cost =
cross-lakehouse reach for the copy/restore step (fine -- same workspace). **Fallback** (lower
plumbing): `init_`-prefixed tables inside `LH_Dentally`. Copy uses the existing
`Promote_Tenant_Stage`-style cross-area Delta copy.

## Flows
- **New real tenant:** `Orchestrate_Onboarding(tenant=100, source=api)` -> clear -> full pull ->
  build-only -> validate -> freeze. Then it's live on the nightly.
- **Nightly:** `Orchestrate_Build(run_dentally_ingest=True)` -> delta pull (all tokened tenants) ->
  Bronze MERGE (upsert, never delete) -> Silver/Gold for those tenants.
- **Rebuild a tenant from snapshot (rare):** `Orchestrate_Onboarding(tenant=100, source=frozen)`
  -> clear -> copy frozen->stage -> build-only. No API call.
- **Synthetic T11/T12:** `seed_onelake` -> `Orchestrate_Build(run_dentally_ingest=False)` (build
  only). Never delta, never frozen. Keeps the regression tenant a clean, deterministic full build.

## Trade-offs accepted (write into the runbook)
- **Delta-only is blind to source deletes.** `updated_after` never returns a record deleted in
  Dentally, so deletions accumulate as stale rows. Parked. Escape hatch: occasionally re-onboard
  the tenant (`source=api`, which clears first) to reconcile, or a periodic key-only anti-join.
- **Transform-logic bug** would need an API re-pull (we froze post-transform, not raw). Accepted.

## Open decisions
- Freeze target lakehouse: separate `LH_Dentally_Onboarding` (default) vs `init_` prefix in place.
- Whether freeze is a flag on `Orchestrate_Onboarding` vs a tiny separate post-validation step.

## Build sequencing
Defer until T100 real-data validation wraps (site/practitioner/phone/hours all green). Then:
(1) `Audit.usp_Clear_Tenant_Data` (+ refactor `usp_Delete_All_Tenant`); (2) create
`LH_Dentally_Onboarding`; (3) `Orchestrate_Onboarding` notebook; (4) strip `@Full_Refresh` from
`Orchestrate_Build` + load SPs; (5) freeze T100's validated stage; (6) switch T100 to the nightly.
