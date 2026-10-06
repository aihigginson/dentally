---
name: metrics-app-health-is-live-compute-is-a-nightly-import
description: In the Fabric Capacity Metrics app the Health page is live but the Compute item table comes from a nightly refresh - do not read one as evidence about the other.
metadata:
  type: reference
---

The two pages of **Microsoft Fabric Capacity Metrics** have different freshness, and nothing on
screen says so:

- **Health** is LIVE. Its "Last 24 hours" / "Last 1 hour" toggle reflects what is happening now.
- **Compute** — in particular the "Items (14 days)" table that breaks CU down by item — comes
  from the app's own semantic model, which refreshes **once a night at 23:01** (about 12 minutes).
  Its "CU % over time" chart therefore ends at the last refresh, and there is no last-hour toggle
  on that page: you narrow time with the slider under the chart, or click a spike and use
  **Explore - TimePoint Detail**.

**Why:** on 2026-10-01 I got this wrong in both directions within an hour. First I quoted a
Health-page figure as proof the day's fixes were working, then — on seeing the Compute chart end
two days earlier — announced the whole app was 20 hours stale and that the earlier figure had been
misleading. A live Health screenshot disproved that. Each correction was confidently wrong.

**How to apply:** for "what is happening right now", use Health. For "what consumed the capacity",
use Compute, and check the dataset's last refresh first (`/datasets/{id}/refreshes`) — today's
incident will not appear until after 23:01. A corollary worth knowing: when the capacity is
rejecting interactive queries, the **warehouse SQL endpoint still answers normally** (measured:
1.0s while the semantic model returned "your organization's Fabric compute capacity has exceeded
its limits"). That contrast localises a problem to interactive load rather than the warehouse.
Related: [[how-to-bounce-the-fabric-capacity]],
[[act-as-reloads-and-re-embeds-ten-reports]].
