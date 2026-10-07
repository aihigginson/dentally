---
name: demo-tenant-bronze-accumulates-every-generation
description: "Bronze has no delete step, so every reseed of tenant 11 layers on top of the last - purge the tenant across Bronze/Silver/Gold before seeding."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T19:52:51.325Z
---

Bronze's load procedures only insert-if-absent and update-if-changed, with **no delete step at
all** — which is deliberate, so the demo tenant survives real-practice ingests that overwrite
the lakehouse stage tables wholesale. The cost is that **every generation of tenant 11 ever
seeded is still in Bronze** unless something explicitly removes it. `seed_bronze.py`'s own
docstring says so; `seed_t11_additive.py`'s says "Bronze accumulates (no delete-not-in-source),
so this only ADDS T11 to the warehouse".

**Why:** by 2026-09-27 tenant 11 held appointments in two state vocabularies — 38,746 lowercase
`completed` from before `_relabel_states` existed, alongside 17,568 `Completed`, each with its
own forward diary into 2027. Because Fabric's collation is case-sensitive
([[fabric-collation-is-case-sensitive]]), Gold counted one set and silently ignored the other:
patients looked dormant, Active Patients read 2,387 against a real 5,673, and Cancel % hit
67.6%. The blend had looked *more* plausible than either generation alone, so it went unnoticed
for weeks. Renaming the site in `API/seed_tenants.py` also had no effect, because the old rows
were never deleted — the warehouse kept showing the previous generation's names.

**How to apply:** before any demo reseed, purge the tenant from **Bronze, Silver AND Gold**
(dims and facts; aggregates rebuild themselves), scoped `WHERE Tenant_ID = 11`, with the
tenant-100 row counts captured before and compared after. Then seed, then verify Bronze before
the chain runs: one state vocabulary, one forward diary, the expected site and practice names,
and no empty tables. A working purge script pattern lives in this session's scratchpad —
enumerate `INFORMATION_SCHEMA` for tables carrying `Tenant_ID` rather than listing them by
hand, because there are 109 of them.
