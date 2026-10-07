---
name: batch-generator-changes-before-reseeding
description: Reseed + chain is expensive enough to throttle the shared capacity; batch fixes first.
metadata:
  type: feedback
---

A demo-tenant reseed is ~500k rows and the Silver→Gold chain is 78 jobs (~8-12 min). Running
that cycle once per generator fix throttled the shared Fabric capacity
(`72ad3bf2-adf1-407d-a1a1-90313099b119`) on 2026-09-26 — `SELECT 1` failed on **both** dev
and prod, because they share it and prod serves the live customer.

**Why:** calibrating generated data against the live tenant surfaces faults one at a time,
and the reflex is to reseed after each. Nine cycles in an afternoon is enough to tip it. The
capacity resource still reports `Succeeded` while throttled — see
[[appdb-read-item-permission-is-a-capacity-symptom]].

**How to apply:** collect generator fixes and verify them OFFLINE first — `generate_tenant()`
in-process against the measured target, which takes ~3 minutes and touches no capacity. Only
reseed once a batch is ready. Reserve full reseed+chain cycles for when the warehouse-side
result genuinely has to be seen (Gold aggregates, metric actuals, DQ scorecard). When the
capacity does throttle, a pause/resume bounce clears it — ask first, it interrupts the live
customer. See [[calibrate-the-demo-tenant-against-live]].
