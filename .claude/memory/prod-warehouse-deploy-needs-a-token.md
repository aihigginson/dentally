---
name: prod-warehouse-deploy-needs-a-token
description: The Test Runner SP cannot reach the PROD warehouse - deploy there with FABRIC_ACCESS_TOKEN instead.
metadata:
  type: project
---

`Scripts/Deploy.ps1` against **prod** fails as the Test Runner service principal:
`Could not login because the authentication failed` (exit 2). Those creds in
`Scripts/fabric_creds.local.ps1` reach dev only.

Use the pre-acquired-token path instead — the same one prod CI uses, and which the
script documents as "OIDC/CI: a pre-acquired AAD token for the warehouse (no client
secret)":

```powershell
$env:FABRIC_ACCESS_TOKEN = (az account get-access-token --resource "https://database.windows.net/" --query accessToken -o tsv)
$env:FABRIC_SERVER = '<prod endpoint ...-eljz...>'
$env:FABRIC_DB     = 'WH_Dentally'
.\Scripts\Deploy.ps1 -Manifest Releases\Vnnn__<name>.manifest
```

Signed in as `admin@analytically.info`, this works (proven on V154, 2026-09-09).
Note the manifest's `TEST` action is **skipped on the token/prod path by design** —
the regression suite runs against the T11 fixture tenant, which does not exist in
prod, so prod is verified separately rather than gated.

**`RUNBOOK.md` §2b (lines 46-52) documents the SP route for prod and is wrong as
written.** See [[dentally-user-activity-is-permission-level]].
