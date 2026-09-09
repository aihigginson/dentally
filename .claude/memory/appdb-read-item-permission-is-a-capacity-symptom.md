---
name: appdb-read-item-permission-is-a-capacity-symptom
description: AppDB "Verify the user has the Read item permission" usually means the Fabric capacity is in transition, not a permissions fault.
metadata:
  type: project
---

When every AppDB endpoint fails at once (`get_roles`, `get_variances`,
`get_plan_capitation`, `get_target_grid` -> "Cannot load" in the UI) with:

```
pyodbc.InterfaceError ('28000', ... Login failed for user '<token-identified principal>'.
Reason: Validation of user's permissions failed. Verify the user has the Read item permission. (18456)
```

**do not start by chasing permissions.** On 2026-09-09 this was the Fabric capacity
in transition (a paused/resizing capacity makes its items fail authorisation, and
Fabric reports that as a permissions error). It cleared the moment the capacity
settled - 12 failures inside a 3-minute window, the entire 14-day history.

**Diagnose from the log window first.** A narrow burst = capacity/transient; a
continuous stream = a real grant problem, in which case check the per-database
`CREATE USER [...] FROM EXTERNAL PROVIDER` grant in `AppDB/README.md` (dev and prod
each need their own).

```powershell
az extension add --name log-analytics
$ws = '3a20ea90-0496-4841-975a-aa438085431b'   # cae-analytically Log Analytics
az monitor log-analytics query -w $ws -o tsv --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(14d) | where Log_s contains 'Read item permission' | summarize failures=count(), firstSeen=min(TimeGenerated), lastSeen=max(TimeGenerated) by ContainerAppName_s"
```
Keep the KQL on ONE line (multi-line strings get mangled), and avoid `first` as an
alias - it is a reserved word.

**Gotcha when checking Fabric workspace roles:** `roleAssignments` reports a service
principal's **object id**, while the app's `CLIENT_ID` env var is its **application
id**. Comparing them directly gives a false "SP has no access". The app SP is named
**Analytically** (appId `ea34f12f...`, objectId `f9efd5d9...`) and is a Member of both
workspaces. See [[prod-warehouse-deploy-needs-a-token]].
