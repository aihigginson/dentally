# Outstanding — Analytically

Living checklist of things that need **you** (portal / business / data-seed actions).
Updated 2026-06-19. Tick items off as they complete.

---

## A. Deploys (technical)  ✅ COMPLETE (dev + prod)

### 1. V015 — patient contact prefs  *(committed `3748478`; dev + prod DONE)*
Re-adds `Use_Email`, `Use_SMS`, `Preferred_Phone` end-to-end. **Order matters** — the
Bronze SP references new `stage_patients` columns that only exist after a reseed:

- [x] **dev:** `python API/seed_onelake.py` *(reseeded 2026-06-19)*
- [x] **dev:** `.\Scripts\Deploy.ps1 -Manifest Releases\V015__patient_contact_prefs.manifest` *(deploy `fc50c1e4`, all 19 OK)*
- [x] **dev:** re-applied `Fabric\Bronze.T15_Test_Data.sql` + reloaded Silver/Gold patients *(deploy `a73cb7a3`)*
- [x] **dev:** refresh the PBI model; add **Use Email / Use SMS / Preferred Phone** to visuals *(done 2026-06-19)*
- [x] **prod:** reseeded via `python API/seed_onelake_prod.py`, then Deploy Warehouse Action (V015, target prod) — **success 2026-06-19**
- [x] **prod:** refreshed the prod semantic model — **success 2026-06-19** (PBI now has the new columns)

### 2. V016 — drop dead `usp_Create_*` procs  *(dev + prod DONE)*
- [x] dev (deploy `2fb2e602`, 19 procs dropped)
- [x] **prod:** Deploy Warehouse Action (V016, target prod) — **success 2026-06-19**

---

## B. Entra / access-model housekeeping

- [x] **3. Delete the old "Dentally DW Test Runner" app registration** (workspace access already revoked). *(done 2026-06-19)*
- [ ] **4. Give `dev@` a permanent minimum licence** before the 60-day PBI Pro trial expires **(~mid-Aug 2026)** — Fabric Free if sufficient, else PBI Pro. *(Only dated item.)*
- [x] **5. Add `viewer@` to `Security.Application_Users`** → demo tenant, so it can see reports. *(done 2026-06-19)*
- [x] **6. Move the prod semantic-model data-source connection to a service principal** — rebound to app SP `ea34f12f` (Service Principal auth), shared with Analytically-Prod-Admin, refresh verified. *(done 2026-06-19)*

---

## C. Logging  *(retention decided: 12 months)*

- [x] **7a. Application logs → 12-month retention + visible** *(done 2026-06-19)* — Log Analytics `workspace-rganalytically3no0` retention set to 365d; app logs the end-user UPN per report load (`[embed-token] upn=… report=…`) → the authoritative per-user report-access audit (the embedded SP model means the PBI activity log shows the SP, not the consumer). KQL in DPIA §4.4 / below.
- [ ] **7b. (roadmap) Power BI/Fabric activity logs** — daily export to durable storage. Low priority: only recurring service-level job is the daily model refresh (one job, one identity).
- [ ] **7c. (roadmap) Entra sign-in logs** — needs **Entra ID P1** to export long-term; deferred while single-operator (enable when staff > 1 / P1 acquired).

---

## D. Security / compliance — external

- [ ] **8. Commission the external penetration test** (scope ready: `PENETRATION_TEST_SCOPE.md`).
- [ ] **9. Get the DPA legally reviewed** before sending to customers (`DPA.md` — drafted, not legal advice).
- [x] **10. "Power BI export disabled"** — **enforced 2026-06-19**: tenant Export-and-sharing settings off org-wide (Export to Excel/.csv, PowerPoint/PDF/image/paginated, Analyze-in-Excel live connection, Download .pbix); embed app also hides context menu + Export-data command (`Web/index.html`). Print + Copy/paste deliberately kept (screen-level, low-risk).

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
