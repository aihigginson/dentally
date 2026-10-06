---
name: how-to-bounce-the-fabric-capacity
description: Suspend/resume the shared F4 capacity with the az fabric extension; the exact commands.
metadata:
  type: reference
---

The capacity is **F4** — small, which is why heavy reseed/chain cycles throttle it
([[batch-generator-changes-before-reseeding]]). Dev and prod share it, so a throttle takes the
live customer's reporting down too.

```
az fabric capacity show    --resource-group rg-analytically --capacity-name analytically
az fabric capacity suspend --resource-group rg-analytically --capacity-name analytically
az fabric capacity resume  --resource-group rg-analytically --capacity-name analytically
```

The `microsoft-fabric` extension is installed (1.0.0b1, preview). Install it with
`az extension add --name microsoft-fabric --allow-preview true --yes` — plain
`az fabric ...` tries to prompt for the install and dies on EOF in a non-interactive shell.
Without the extension, the raw ARM API works:
`az rest --method post --url "https://management.azure.com<resource-id>/suspend?api-version=2023-11-01"`
(resource id: `/subscriptions/<sub>/resourceGroups/rg-analytically/providers/Microsoft.Fabric/capacities/analytically`).

**How to tell a throttle from slow work:** time `EVALUATE ROW("x", 1)` through
`executeQueries`. It touches no data, so whatever it takes is pure admission delay. Throttled it
returns in ~20s; healthy, 0.3s. Every other query sits on top of that floor, which is why a report
page firing 30-80 queries reads as "hung" and why a trivial query can look slower than a complex
one. Do not attribute that floor to model reload, RLS or DAX -- on 2026-09-28 a cold model load
measured 1.0s once the throttle was gone, having looked like 161s while it was there.

**Why it matters:** `properties.state` passes through `Pausing` → `Paused` → `Resuming` →
`Active`, and a suspend takes a minute or two. Poll for `Paused` before resuming rather than
firing both straight after each other. Verified 2026-09-26: warehouse data survives a bounce
untouched on both environments. `state` reported `Active` while the capacity was in fact
throttled, so Active is not evidence of health — see
[[appdb-read-item-permission-is-a-capacity-symptom]]. Ask before bouncing: it interrupts the
live customer, even though a throttle already has.

Verified again 2026-09-28: a suspend/resume cleared the carryforward outright -- the same
three queries went 20.5s / 20.3s / 20.5s before the bounce and 0.3s / 0.4s / 0.3s after,
about ten minutes' total disruption.

**A full-rebuild release throttles the capacity, and doing both environments compounds it.**
On 2026-09-28 V197 rebuilt Gold.Fact_Revenue plus three dependent aggregates on dev and then
on prod inside twenty minutes; the trivial query went to 161s in DEV and 163s in PROD at the
same moment -- eight times the ~20s floor seen earlier the same day. Two workspaces degrading
together is the signature: a single model's reload cannot do that. Expect it after any
release whose manifest re-runs whole-table loads, and either sequence the remaining heavy
work (promotion, refresh) BEFORE one bounce, or accept bouncing twice.
