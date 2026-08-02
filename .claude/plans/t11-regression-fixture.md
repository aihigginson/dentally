# T11 Regression Fixture — rebuilt from real Tenant 100 profiles

**Goal:** a deterministic synthetic **Tenant 11** (~half the size of the real Tenant 100), whose data
*profiles and typing* mirror the real practice, so regression tests catch only intended consequences of
future changes. Zero risk: T11 is fully isolated from the real Tenant 100, all on dev.

Generator = `API/generate_data.py` (`random.seed(42)`, `tdef`-driven per-tenant config + `gen_*`
entity functions) → `API/seed_onelake.py` writes Delta to OneLake → Bronze→Silver→Gold →
`Capture_Baseline` locks the known-good numbers.

## Tenant 100 profile (captured 2026-08-02, real data on dev)

| Entity | Tenant 100 | T11 target (~½) |
|---|---:|---:|
| Patients | 27,773 (6,974 active) | ~14,000 |
| Appointments | 174,695 | ~87,000 |
| Treatment plans | 69,090 (67,571 completed) | ~35,000 |
| Invoice items | 91,311 (avg £80.12, total £7.32M) | ~46,000 |
| NHS claims | 13,096 | ~6,500 |
| Recalls | 9,159 | ~4,600 |
| Appt date span | 2012-02-29 → 2028-03-20 (16 yr) | keep, deterministic via GENERATE_AS_OF |

- **Sites:** 1 — "Maple Dental" (single-site practice).
- **Practitioners:** 9 Dentists + 6 Hygienists active (no ortho, no TCO). T11: ~5 dentists + 3 hygienists.
- **Payment plan mix (by patient):** Private 47% (13,094) · NHS 38% (10,550) · IRH Fees 9% (2,437) ·
  Denplan tail 6% (C 585, Essentials A 394, B 254, D 159, Essentials B 103, A 80, E 19, Children 12) ·
  Referral 65 · MUFC 20 · Capitation 1.
- **Plan monthly fees (£/mo):** 12, 18, 28.50 (default), 32, 40, 51, 65, 80 across the Denplan variants.
- **Treatment plan funding:** ~19% NHS-funded (13,222), ~45% private-funded (31,237, avg **£277.58**),
  rest zero-value "plan-style"/membership evidence. Avg UDA/plan 1.51.
- **Appointment states:** Completed 60% (104,408) · Cancelled 18% (31,406) · Pending 11% (19,462) ·
  Confirmed 9% (16,393) · DNA 2% (3,012).
- **Appointment reasons:** Exam 26% · Continuing Treatment 15% · HEX 13% · Hygiene 9% · NOT WORKING 8% ·
  Lunch/Other/Scale&Polish tail. (Non-clinical Lunch/NOT WORKING blocks ARE present — keep them.)
- **NHS contract:** single dental contract, UDA target ~4204/yr (drives Fact_NHS_Contract_Week).
- **Acquisition sources / cancellation reasons:** small tenant-specific lists (profile the exact values).
- **Completed appt duration:** realistic per-reason (exam ~short, treatment longer) — encoded in gen_appointments.

## Build steps
1. **Add a T11 `tdef`** in `generate_data.py`: `tenant_id: 11`, `n_patients: 14000`, single site
   "Maple Dental", 5 dentists + 3 hygienists, `nhs: True`, `has_ortho: False`, `price_mult` tuned so
   invoice avg ≈ £80 / avg private plan ≈ £278. Payment_plans list = NHS + Private + IRH Fees +
   the Denplan variants with the real monthly fees. Patient plan-assignment weighted to the mix above.
   Single NHS contract UDA ~4204. Real-shaped acquisition/cancellation lists.
2. **Verify the generator's knobs** map cleanly: how `gen_patients` assigns plans (weight to real mix),
   history depth, `_site_patient_split` (single site = 1.0), per-patient appointment counts.
3. **Generate** — `python API/generate_data.py` (deterministic; produces T11 JSON/Delta staging).
4. **Load** — `API/seed_onelake.py` writes T11 Delta → run Bronze→Silver→Gold for tenant 11.
   Re-add T11 to `Audit.Tenants.Data.sql` seed (Is_Active=1) so builds include it.
5. **Baseline** — `Scripts/Run_Tests.ps1` / `Capture_Baseline` on the deterministic T11 → lock the
   122 metrics + 45 reconciles. This also clears the stale-baseline `dw-tests` red.

## Decisions (finalised 2026-08-02)
- **Clinicians:** smaller set — **5 dentists + 3 hygienists** (8 total), single site.
- **History:** **6 years** (~2020 → GENERATE_AS_OF 2026), not the full 16 — smaller/faster fixture that
  still exercises recall / lapsed / retention / NHS-year logic.
- **Patients:** keep the **plan-mix proportions**, but **exclude the long-dormant tail** — generate only
  the cohort with activity inside the 6-yr window (active + recently-lapsed). Net ≈ half of Tenant 100's
  relevant base (~12–14k), with a realistic active-vs-recently-lapsed split (NOT the deep-dormant 20k).
  Per-patient appointment/plan/invoice ratios kept real (so volumes scale with the patient count).
