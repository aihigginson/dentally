---
name: never-run-exploratory-dax-on-the-shared-capacity
description: The F4 serves the live customer. An unbounded DAX probe took the site down on 2026-10-06; never prototype DAX against it.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-06T15:21:02.237Z
---

**On 2026-10-06 I took the site down.** Testing whether a counterparty name could be produced by a
measure, I ran a `SUMMARIZECOLUMNS` over Full Date x Patient x Plan with a `REMOVEFILTERS` measure.
A measure in a detail table destroys auto-exist, so the engine had to materialise roughly 336M
combinations. It was refused at the 1GB per-query ceiling — and I ran it a **second** time with a
tweak, and was starting a third when the owner stopped me. The owner: *"That was more than careless
that was negligent. You brought the whole site down with something that was ludicrous."*

**Why:** there is ONE F4, shared by dev and prod, and prod is a live dental practice. Interactive
overage carries forward and starts rejecting requests — my probe did not just cost CUs, it denied
service to a paying customer. The 1GB rejection is not a free "no": the query still consumed the
capacity while being built.

**How to apply:**
- Never run exploratory or speculative DAX against this capacity. Not "just once to check".
- A measure referenced by a **detail table** is already known to be wrong — see
  [[a-detail-table-needs-a-column-not-a-measure]]. Do not test what that memory already answers.
- If a query must run, bound it first: a single practitioner AND a single month AND `TOPN`, and
  reason about the crossjoin size BEFORE sending it.
- A query refused for memory is a STOP, not a prompt to tweak and resend.
- Recovery is [[how-to-bounce-the-fabric-capacity]], and bouncing hits prod — so it is the owner's
  call, not mine.

Related: [[a-report-render-costs-about-27-cu-seconds]], [[scale-target-is-100-practices]],
[[batch-generator-changes-before-reseeding]] (same lesson, different tool: verify offline first).
