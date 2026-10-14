---
name: t11-is-both-demo-and-regression-fixture
description: Tenant 11 serves two conflicting purposes; changing it for one breaks the other.
metadata:
  type: project
---

Tenant 11 is both the **demo practice** ("look around" data, dev only, rebuilt weekly) and
the **manual regression fixture** (`API/seed_t11_additive.py`, T11-only, not wired into CI).

**Why:** these pull in opposite directions. A regression fixture wants a frozen random stream
so baselines stay comparable; a demo wants its data reshaped whenever it stops looking like a
real practice. As of 2026-09-25 the demo need has won repeatedly — the three-year window
(`GENERATE_YEARS_BACK`, from "no need to generate anything before 2024"), then a run of
calibration fixes, each of which shifts the stream and invalidates any stored baseline.

**How to apply:** treat the T11 regression baselines as stale, not as a constraint — do not
preserve rng-draw counts in `generate_data.py` to protect them. If regression testing is
revived, give it its own tenant number first. See
[[calibrate-the-demo-tenant-against-live]].

**Measured 2026-10-14, running the gate after V220.** The baseline was captured **16/09/2026**, so
every reseed since then shows as a failure: 56 of 110 regression checks CHANGED, and ALL 56 are
tenant 11 (including `GOLD_PATIENTS_T11_INC_SENTINEL`, which does not end in `_T11` and so escapes
a naive filter). Bronze counts moved -- 7,860 patients to 4,000 -- which is upstream of anything a
warehouse refactor touches, so that is the reseed and nothing else. The 41 RECONCILE checks all
PASS, which says the reseeded data is internally consistent Bronze-to-Gold.

**The gate is nearly blind to the Gold load procedures.** Matching each metric's SQL_Text against
the objects V220 changed: `Fact_Invoices` has 3 checks and `Dim_NHS_Contracts` 1. `Fact_Revenue`,
`Fact_KPI_Snapshot`, `Fact_New_Patients`, `Fact_Appointment_Journey`, `Xero_Finance_Lines`,
`Billing.Invoice_Line`, `Dim_Patient_Data_Quality` and `vw_Dim_Date` have **none at all**. So a
green run is not evidence that a change to those is correct, and 56 permanently-red checks mean
the gate cannot fail usefully either. Do not read `Run_Tests.ps1` as validation of a Gold refactor
-- capture before/after figures and difference them instead, which is what actually caught nothing
and proved everything for V220.

`-Promote` re-greens it by moving Current to Baseline; only worth doing once the current T11 data
is the intended state.
