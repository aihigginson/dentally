# Prod promotion runbook — 2026-07-28

Promotes the 28-commit dev delta. Prod warehouse at **V113**. Four channels; run in order.

## 0. Pre-check
- Dev model HAS `Course Age Bucket` (csx applied) + Diary Fill — confirmed.
- Dev workspace reports published (incl. registered magnifier images) — confirmed.
- No new report **items** (Aged Plans are lenses/pages inside existing Clinical + My Data),
  so **no new `REPORT_ID_*` env vars** needed on prod.

## 1. Warehouse → prod  (deploy-warehouse.yml, batch V114 + V115)
```
gh workflow run "Deploy Warehouse" \
  -f manifest="V114__diary_break_dedup.manifest,V115__security_access_holders_only.manifest" \
  -f target=prod -f skip_tests=true
```
- OIDC-gated + `prod` GitHub Environment (approve if a reviewer is set).
- Manifests are on dev; merging PR #66 also puts them on main (prod deploy checks out the
  default branch — see [[feedback_prod_deploy_reads_dev_branch]]). Safest: **merge PR #66 first**,
  or dispatch on the branch that has V114/V115.
- V115 note: on the next prod access-sync, existing all-zero no-access rows clear; owners
  (all flags 1) are never deleted — spot-check `Security.Application_Users` after.

## 2. App → prod  (merge PR #66)
- Merge **PR #66** (dev→main, reviewed). `deploy-prod.yml` fires on the `Web/**` change and
  deploys the container. Covers: Clinician=My Data only, practitioner-filter lock, sign-out.

## 3. Model + Reports → prod  (Fabric DEPLOYMENT PIPELINE, dev workspace → prod)
- Promote in the Fabric UI. Carries the semantic model (with `Course Age Bucket`) + all report
  items (Aged Plans lenses, drill icons + images, detail pages, By-Category default, palette,
  Diary Fill). See [[feedback_fabric_promote_pipeline]].

## 4. Prod Orchestrate_Build
- Run Orchestrate_Build on **prod** → reloads data with V114 (diary dedup) + V115, and the
  post-load model refresh **populates `Course Age Bucket`** + refreshes the RLS `Application Users`
  snapshot so newly-provisioned users resolve.

## Verify
- Aged Plans lens shows value/count by bucket; drill-through lists patients (+ phone/email).
- Diary worked-hours sane (no negatives); Open Courses value = Completed=0 & NHS_Charge=0.
- A clinician sees only My Data, practitioner filter locked; sign-out works.
