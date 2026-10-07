---
name: act-as-reloads-and-re-embeds-ten-reports
description: "SETTLED 2026-10-02 - one user switching practice 4-5 times took BOTH dev and prod to a 20s admission delay, so the ten-report preload is now off behind PRELOAD_SECTIONS."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-02T07:07:10.869Z
---

The practice picker and the staff client picker both end in `location.reload()`
(`Web/index.html`). That is **correct** and the code says why: RLS scope is baked into the embed
token as `customData`, so existing embeds hold tokens minted for the previous practice and cannot
be re-filtered in place.

But a reload runs `startApp()`, which embedded the first section and then preloaded the other nine
at 1.5s intervals. **One "act as" switch therefore cost ten embed tokens and ten report renders**,
each firing dozens of DAX queries.

**MEASURED 2026-10-02, deliberately trying to break it as a SINGLE user:**

        baseline            dev  0.34s   prod  0.27s
        after 4-5 switches  dev 20.36s   prod 20.42s    THROTTLED, and pinned at ~20.3s
                                                        for 4+ minutes after clicking stopped

**==> PROD DEGRADED IN LOCKSTEP WITH DEV. <==** It is one F4. A staff member switching practice in
DEV takes the LIVE CUSTOMER from 0.27s to 20 seconds. That, not dev's own comfort, is what settled
it: the preload was spending the paying practice's budget. (This also confirms the 2026-10-01
rejection incidents, where 68 queries were refused across both workspaces after "act as" use while
the warehouse was idle and Spark was ~5% of the day.)

**Outcome: the preload is OFF**, gated on `const PRELOAD_SECTIONS = false` in `Web/index.html`
(commit 5e3caa5), with the measurement recorded beside it. Cost of off: a section not yet visited
takes a ~3s first render instead of instant, once per section per session.

Deliberately NOT narrowed to the staff/act-as path, though that was the lighter option considered:
it would leave a customer login at ten renders and the ceiling at roughly four concurrent logins --
survivable for one practice, useless against [[scale-target-is-100-practices]], and it would bury
the cost where it is hardest to observe.

**How to apply:** turning it back on is one word, but the case for preloading was always
statistical -- with many users, simultaneous logins are rare and bursts smooth out. On an F4 one
session's burst IS the entire five-minute budget, so the statistics never get a chance to help. It
earns its place again only at a SKU where one session is small against the average, and
**re-measure with the probe first** rather than assuming a bigger number fixed it. Corollary worth
keeping: with the preload off a page load is one render instead of ten, roughly a 10x headroom
gain, which is what makes "can an F4 serve ten simultaneous users" plausible at all. And do NOT
bounce the capacity for this -- give the smoothing window five minutes
([[how-to-bounce-the-fabric-capacity]]).
