---
name: container-job-failures-are-unmonitored
description: Nothing alerts on a failed Container Apps Job — sales-monitor-dev ran red for 8 days unseen; check `az containerapp job execution list` by hand.
metadata:
  type: project
---

The health monitor (`/api/monitor/health`) scans `Audit.Process_Execution_Log` and
`Audit.Ingest_Log`. **The Container Apps Jobs write to neither**, so a job that fails every
night produces no alert, no email and no warehouse row — the only trace is the execution
status in Azure and the console lines in Log Analytics.

Found 2026-10-26: `caj-sales-monitor-dev` had failed **every run since 19 October**, eight
days, with its status plainly `Failed` in Azure the whole time. Nothing was watching.

The jobs, as of 26/10/2026:

| job | cadence | writes to Process_Execution_Log? |
|---|---|---|
| `caj-capacity-schedule-prod` | hourly at :45 | no |
| `caj-appdb-sync-dev` / `-prod` | every 10 min | **yes** (`appdb_sync.access`) |
| `caj-sales-monitor-dev` / `-prod` | daily 06:40 | no |

`appdb_sync` is the partial exception and shows the other half of the trap: the JOB reported
`Succeeded` through 180 consecutive inner failures on PROD (24–25/10,
`Input_Stage.Client does not exist`). So job status and step status are independent — neither
one alone tells you a feed is healthy.

**Why:** two different blind spots. Sales monitor failed loudly where nobody looks; appdb sync
failed quietly where the status says fine.

**How to apply:** when asked to check general health, do not stop at the warehouse logs —
run `az containerapp job execution list -n <job> -g rg-analytically` for each job and read the
last several statuses, then cross-check `Audit.Process_Execution_Log` for the inner result.
Console output is in Log Analytics (`ContainerAppConsoleLogs_CL | where ContainerJobName_s ==
'<job>'`) and survives after the replicas are gone, which `az containerapp job logs show`
does not. Extending the health monitor to cover job executions is unbuilt and has not been
proposed to the owner. Related: [[a-silent-except-froze-patient-stats]],
[[piping-to-tail-hides-the-exit-code]], [[sales-monitor-shape-and-deferred-card-stages]].
