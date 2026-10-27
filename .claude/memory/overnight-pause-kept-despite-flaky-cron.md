---
name: overnight-pause-kept-despite-flaky-cron
description: "SETTLED -- the overnight capacity pause stays, GitHub cron unreliability accepted, owner checks the site each morning."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-22T08:19:03.738Z
---

The capacity schedule pauses overnight and resumes at 06:00 UK. GitHub cron is best-effort:
on the first night live it fired 3 of 8 expected runs and **neither** resume cron ran, so
PROD showed the maintenance page from midnight until it was resumed by hand at 09:20.

**UPDATE 2026-10-23: the GitHub `schedule` trigger is gone and is not coming back.** Measured
over 09–23/10, not one of fourteen scheduled firings ran on time. The schedule now runs as the
Container Apps Job **`caj-capacity-schedule-prod`**, hourly at :45, from `Web/capacity_schedule.py`
— and it fires to the minute. Verified 26/10 in the activity log: suspend 23:46, resume 05:45,
F2 at 17:45, F4 at 21:45, every day without a miss. So a missing morning is now unlikely, and
"the site is down" is much more likely to be something else — check `az fabric capacity show`
before assuming the schedule failed, because the Metrics app lies about state
([[metrics-app-health-is-live-compute-is-a-nightly-import]]).

The owner's decision: **keep the pause.** The saving matters more than the risk while there
is one customer, and they will check the site in a morning now they know it is temperamental.

The workflow survives as the MANUAL lever for when the capacity is in the wrong state and you
want it fixed now. One command from the repo folder -- no arguments, it derives the target SKU
from the current UK time itself:

    gh workflow run capacity-schedule.yml

Roughly 60-90 seconds to come back.

**Why:** the asymmetry is real (a missed pause costs pennies, a missed resume costs the
customer their morning) but it is the owner's call, and they have taken it with the fault in
front of them. Moving the scheduler to Azure Automation is the eventual fix, not today's work.

**How to apply:** do not re-propose stopping the pause or adding redundant crons -- see
[[dont-re-raise-settled-decisions]]. If the site is down in the morning, run the dispatch and
move on. Related: [[how-to-bounce-the-fabric-capacity]],
[[appdb-read-item-permission-is-a-capacity-symptom]],
[[never-run-exploratory-dax-on-the-shared-capacity]].
