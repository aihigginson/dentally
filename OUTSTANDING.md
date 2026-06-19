# Outstanding — Analytically

Living checklist of things that need **you** (portal / business / data-seed actions).
Updated 2026-06-19. Tick items off as they complete.

---

## A. Deploys (technical)

### 1. V015 — patient contact prefs  *(committed `3748478`; dev deploy IN PROGRESS)*
Re-adds `Use_Email`, `Use_SMS`, `Preferred_Phone` end-to-end. **Order matters** — the
Bronze SP references new `stage_patients` columns that only exist after a reseed:

- [ ] **dev:** `python API/seed_onelake.py`  *(opens a browser for auth; rewrites the stage Delta with the new columns. Reseeds T11–14 — data is byte-identical except the 3 new columns, so no drift.)*
- [ ] **dev:** `.\Scripts\Deploy.ps1 -Manifest Releases\V015__patient_contact_prefs.manifest`  *(now recreates the Stage views first, then Bronze→Silver→Gold→PBI)*
- [ ] **dev:** re-apply `Fabric\Bronze.T15_Test_Data.sql`  *(the Bronze drop/create clears T15; new cols are nullable so the existing insert still works)*
- [ ] **dev:** refresh the PBI model; add **Use Email / Use SMS / Preferred Phone** to visuals as wanted
- [ ] **prod:** repeat seed (if prod data is reseeded that way) + `$env:FABRIC_SERVER='...-eljz...'` then the same manifest + refresh

> Note: the first dev manifest run stopped at step 2 (Stage didn't have the columns yet) — expected. Just do the reseed, then re-run the whole manifest.

### 2. V016 — drop dead `usp_Create_*` procs  *(dev DONE)*
- [x] dev (deploy `2fb2e602`, 19 procs dropped)
- [ ] **prod:** GitHub *Deploy Warehouse* action target=prod (or `$env:FABRIC_SERVER='...-eljz...'` + `.\Scripts\Deploy.ps1 -Manifest Releases\V016__drop_dead_create_procs.manifest`). Idempotent.

---

## B. Entra / access-model housekeeping

- [ ] **3. Delete the old "Dentally DW Test Runner" app registration** (workspace access already revoked).
- [ ] **4. Give `dev@` a permanent minimum licence** before the 60-day PBI Pro trial expires **(~mid-Aug 2026)** — Fabric Free if sufficient, else PBI Pro. *(Only dated item.)*
- [ ] **5. Add `viewer@` to `Security.Application_Users`** → demo tenant, so it can see reports.
- [ ] **6. Move the prod semantic-model data-source connection to a service principal / service account** (currently a personal OAuth — `ACCESS_MODEL.md` §4b).

---

## C. Logging  *(retention already decided: 12 months)*

- [ ] **7. Enable + retain Entra sign-in logs + Power BI/Fabric activity logs** (export to durable storage).

---

## D. Security / compliance — external

- [ ] **8. Commission the external penetration test** (scope ready: `PENETRATION_TEST_SCOPE.md`).
- [ ] **9. Get the DPA legally reviewed** before sending to customers (`DPA.md` — drafted, not legal advice).
- [ ] **10. Enforce "Power BI export disabled"** at the Fabric capacity / tenant admin setting (documented as agreed control; not yet switched off).

---

## E. Open `[CONFIRM]` business decisions in the docs

- [ ] **11. Active-practice data retention period** (full Dentally history vs e.g. 7 years) — DPIA §6.2.
- [ ] **12. Exact authorised-user role list** — DPIA §1.3 / DPA Schedule 1.
- [ ] **13. RPO/RTO + Fabric PITR / restore retention** — DPIA §5.3.
- [ ] **14. (Lower) Customer-managed keys (CMK)** — currently Microsoft-managed; noted as a TODO, not required.

---

## F. Lower priority / parked

- [ ] **15. Real Dentally pipeline column trim** (prod Stage still ~49 cols) — only matters once real data flows; the warehouse drops them regardless.
- [ ] **16. Uncommitted on disk:** `PBI/*.pbix` + `.claude/settings.local.json` — your report work; commit or leave.
