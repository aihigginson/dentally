# Consolidation & Replan — 2026-07-08

Single source of truth after a wide-ranging session. Groups everything into: what's live, what's
committed-but-pending, the metric-fix worklist, prod readiness, and open architecture — then a replan.

## 1. Live / done (dev)
- **Real Maple (Tenant 100) onboarded to dev** and validated: all Gold facts match stage counts
  (tpi 249,441; treatment_appointments 548,686), no `Dim_Patients` dup, appointment **site
  attribution = 0 unresolved**, timing chain populated, `Fact_Metric_Actuals` 219k rows / 0 NULL date.
- **Warehouse manifests V046–V049 = SUCCESS** in dev `Migrate.Deploy_Log` (diary day/unavailable/
  days-worked; `usp_Clear_Tenant_Data` + `usp_Delete_All_Tenant` refactor).
- **Capacity cost controls (committed + working):**
  - `Scripts/Capacity.ps1` — `pause` / `resume` / `f2` / `f4` / `f8` (pay only for hours used).
  - **Holding page** on the app when the capacity is paused (tested end-to-end).
  - Lesson: **F2 (2 CU) is fine for steady state** (~18% util). The overload was heavy Spark ETL
    bursts + report-serving concurrency during a debugging day — NOT data volume. Autoscale-Billing-
    for-Spark is not exposed in the Azure portal for this capacity; use scale-for-the-window (F4/F8
    around an onboarding) or run heavy ETL overnight.

## 2. Committed, pending deploy / Fabric import
- **V050 (Lapsed 2-cohort flow)** — SQL layer deployable (`Releases/V050__lapsed_metric_rework.manifest`).
  Deploy + build makes the WAREHOUSE data correct; the **card measure rework is still pending** (see §3).
- **Notebooks needing (re)import to the Fabric workspace** (edited this session):
  - `Ingest_Dentally` — adaptive date-windowing for the tpi/treatment_plans deep-offset 413.
  - `Freeze_Onboarding_Stage` — new (stage↔init_stage snapshot, `init_` prefix).
  - `Orchestrate_Onboarding` — reworked to `clear → pull → freeze → SQL-endpoint sync-poll → build`
    (fixes the endpoint-sync race that gave an empty build the first prod-style run).
  - `Orchestrate_Build` — 180s settle before the model refresh (endpoint-sync lag).

## 3. Metric-fix worklist (from the real-data review)
| Metric | Diagnosis | Status | Size |
|---|---|---|---|
| **Lapsed Patients** | was single wrong point-in-time (17,425 = whole base) | **data DONE (V050)**; measure rework pending | measure = model change |
| Treatment Acceptance | data has no declined treatment (only 8/249k items) → always ~100% | **DROPPED** (decided); measure+config removal + user removes visual — pending | small |
| Email/Phone Rate | computed over all 27,748; should be over **active** (~94% / ~100%) | diagnosed | **quick** (measure) |
| NHS Revenue / Contracted | contract `Target` + `UDA_Value` in Bronze; not applied | diagnosed | medium (new Gold agg: claim `awarded_uda` × `uda_value`) |
| Open Courses / Value | plan-level `completed`; should be **item-level accepted(scheduled)-not-completed**, plan-completion cascades to items | diagnosed | medium (Gold logic) |
| Exam Ratio | HEX/exam codes not categorised and/or hygiene in denominator | needs investigation | medium |
| DNA / Cancellation / BBYL | "low but plausible" | watch only | — |

**Lapsed measure rework (the pending piece):** card value = a live base measure (currently reads
`_KPI Snapshot`). To make it flow: add model relationship `List Patients[fk Date Lapsed] → List Date
[pk Date]`, rewrite `[Lapsed Patients]` = `CALCULATE(COUNTROWS('List Patients'), NOT ISBLANK([Lapsed
Type]), USERELATIONSHIP(...))`, add the two cohort measures + cards, and change
`TabularEditor_MetricActuals.csx` lapsed mapping `"snap"` → cumulative. Apply + test in Tabular Editor.

## 4. Prod readiness
- Runbook: `.claude/plans/prod-onboarding-runbook.md` (7-phase; freeze via `init_stage_*`).
- Onboarding/delta architecture: `.claude/plans/onboarding-delta-build-architecture.md`.
- Before a clean PROD onboarding: import the 4 reworked notebooks to the prod workspace; deploy
  warehouse through V050 to prod; Maple token in `dentally-tokens-prod`; repoint prod semantic model.
- The metric fixes are mostly model-side (measures) — prod can be onboarded first, measures fixed after.

## 5. Open architecture (parked)
- **Delta run never actually tested** (`Orchestrate_Build run_dentally_ingest=True`, incremental).
- **Delta ↔ onboarding interweave**: a tenant mid-onboarding must be excluded from the nightly delta
  (needs a state flag on `Audit.Tenants`); scheduling so a multi-hour onboard doesn't hit the 02:00 build.
- **Recalls full-refresh-every-run** (delta can't see deletes) — not built.

## 6. Proposed replan (next session, in order)
1. **Deploy V050** + verify lapsed data in the warehouse.
2. **Finish Lapsed measure** (Tabular Editor: relationship + measures + cards) → card correct.
3. **Quick wins**, cheapest first: Email/Phone (measure) → Open Courses (Gold) → NHS Revenue (Gold agg)
   → Exam Ratio (after code-categorisation check). Deploy + rebuild + retest each.
4. **Acceptance cleanup** — remove the measure/config/spider refs; user removes the visual.
5. **Prod**: import reworked notebooks, deploy warehouse to prod, run `Orchestrate_Onboarding` prod.
6. **Delta**: first real delta run + the onboarding-exclusion state flag.
