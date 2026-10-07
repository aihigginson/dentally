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
