# Prod Deployment Runbook — V070–V081 + model + report

Moves the recall / scheduling / at-risk / target-proration work from dev to **prod**.
Prod is a **separate Fabric workspace**; the warehouse deploys via the `Deploy Warehouse`
GitHub action (manual, OIDC, no stored secret). The app/model/report are separate steps.

Dev already has V070–V081 + the Tabular Editor scripts applied. This brings prod level.

---

## 0. Pre-flight (do first)

- [ ] **Get the code onto `main` via a reviewed PR.** All this work is on
      `journey-fact-windowed`. The Deploy Warehouse action deploys the **remote** file content
      of the branch you dispatch, and prod should go from `main` (reviewed), not a feature branch.
      → open PR `journey-fact-windowed → main`, review, merge. (Fabric/Releases/.claude paths do
      NOT trigger the app `deploy-prod.yml`, which is Web/** only — safe.)
- [ ] **Confirm prod's current migration level.** On the prod warehouse, check
      `Migrate.Deploy_Log` for the last applied `Vnnn`. Everything after that up to V081 is the
      pending set (expected: V070→V081).
- [ ] **Timing.** Gold facts/aggregates are DROP/CREATE — they're briefly empty between schema
      deploy and the rebuild. Deploy in a low-usage window, or right before the 02:00 build.

---

## 1. Warehouse schema → prod

Run **Actions → Deploy Warehouse → Run workflow**, `target = prod`, once per manifest, **in order
V070 → V081** (prod Environment approval fires if a reviewer is set).

- The action authenticates the **prod SP via OIDC** and applies the manifest with `Deploy.ps1`
  against the prod endpoint (`…eljzajgm5cpe5i64szgon7sej4…`). Each manifest is logged in
  `Migrate.Deploy_Log` (skipped if already applied), so re-runs are safe.
- Migrations ride along: V073 (drop stale passthrough views + regenerate PBI views), V079 (load
  Fact_Patient_At_Risk + regenerate PBI views). Both idempotent.
- **Note:** these steps deploy **schema + a one-off load**; the authoritative data comes from the
  rebuild in step 2. Don't rely on per-manifest EXECs for the final data.
- [ ] After the run, re-check `Migrate.Deploy_Log` shows V070–V081.

> **Optional simplification:** instead of 12 dispatches, I can build a single
> `V082__prod_cutover.manifest` that DEPLOYs the union of changed files + runs the two migrations,
> so it's **one** prod dispatch. Trade-off: prod's log shows V082 rather than each V070–V081. Say
> the word and I'll assemble it.

---

## 2. Data rebuild → prod

- [ ] Run the **prod Orchestrate_Build** (`@Mode='PROD'`, full — not delta) so the DROP/CREATE
      tables repopulate: aggregate (+ Chair_Hours/Tracked), Fact_Practitioner_Diaries (+ dummy
      entries), Fact_Metric_Actuals (new recall + scheduling metrics + fixed Overdue Recalls),
      Fact_Patient_At_Risk. Or let the 02:00 overnight build do it.
- [ ] Sanity-check in the prod warehouse (SQL): Chair Utilisation ~mid-70s, Dentist/Hygiene
      Retention Outlook populated, Overdue Recalls small (Unbooked + no-reminder), Fact_Patient_At_Risk
      has rows, `GOLD_AGG_PATIENT_AT_RISK` ran (check Audit run log).

---

## 3. Semantic model → prod  (Tabular Editor, your Desktop job)

Prod has its **own** `DM Dentally` model — the scripts + relationships must be applied there too.

- [ ] Point Tabular Editor at the **prod** model (prod workspace XMLA).
- [ ] Add the **two inactive NHS relationships** (same as you added on dev):
      `'_Treatment Plans'[fk Date Start]` → `'List Date'[pk Date]` (inactive), and
      `'_NHS Claims'[fk Date Approval]` → `'List Date'[pk Date]` (inactive).
- [ ] Apply the section scripts (Revenue, Patients, Scheduling, NHS, spiders) **then**
      `TabularEditor_MetricActuals.csx` with `MODE="apply"` (it retargets, so runs last).
- [ ] **Refresh** the prod semantic model. If measures come back blank, **re-refresh** — that's
      the SQL-endpoint sync lag after a warehouse rebuild, not a data bug.
- [ ] Confirm the prod model points at the **prod** warehouse, not dev.

---

## 4. Report / visuals → prod  (your Desktop job)

Measure renames/removals break the cards that referenced them — repoint in the prod report:

- `Retention Outlook` → **`Dentist Retention Outlook`** + **`Hygiene Retention Outlook`**
- `Immediate Forward Utilisation` → **`Diary Fill (Forward)`**
- `Chair Utilisation` — name kept, **value now means actual capped chair time** (was ≈ Diary Fill)
- New cards available: `Diary Fill`, `Patient Tracked in Surgery`, `Dentist/Hygiene Recall Conversion`,
  `At Risk Patients` (+ the `PBI.[_Patient At Risk]` list), `Open Courses Without Appointment Value`
- `Overdue Recalls` — same card, correct number now (no rebuild needed)

---

## 5. Verify (prod isn't auto-gated — the dw-tests only run against the dev test tenant)

- [ ] Spot-check prod cards vs the warehouse SQL for a couple of metrics.
- [ ] Filters: pick a practitioner → agnostic metrics (Retention Outlook, Email) show global + grey,
      NOT "No data". Lapsed / New Patients targets prorate on Last 3 Months.
- [ ] Open Courses Value colours against its band (`within`), not higher-is-better.

---

## 6. Rollback / safety

- No destructive migrations beyond DROP/CREATE of derived Gold tables. If a deploy half-lands, the
  fix is to re-run the prod Orchestrate_Build — it rebuilds every DROP/CREATE table from Silver/Gold.
- Model + report changes are reversible in Desktop; keep the previous prod `.pbix` until verified.

---

## Deferred (explicitly NOT in this cutover)

- The **target model redesign** (`.claude/plans/target-model-redesign.md`) — next piece, after prod is stable.
