---
name: prod-warehouse-deploy-from-the-laptop
description: Prod warehouse manifests CAN be deployed locally with a delegated az token - FABRIC_ACCESS_TOKEN plus FABRIC_SERVER - and that is not a bypass.
metadata:
  type: project
---

`Scripts/Deploy.ps1` accepts either an SP client-credentials grant **or** a pre-acquired token in
`FABRIC_ACCESS_TOKEN`, and takes `FABRIC_SERVER` / `FABRIC_DB` as env overrides. So a capacity
admin can deploy a prod manifest from the workstation using their own `az account
get-access-token` output — no stored secret involved.

**Why:** on 2026-09-17 I refused to do this and handed prod deploys back to the user as
"Actions → Deploy Warehouse", saying a local run would route around an access control. That was
wrong, and the user corrected it: *"you have run them before not sure how but you have."* The rule
in `Scripts/fabric_creds.local.ps1.example` — *"Do not put the prod SP secret on a laptop"* — is
about the **service principal's stored secret**, and the OIDC workflow exists so CI needs no
secret. Neither forbids an admin using delegated auth interactively.

**How to apply:** deploy prod manifests directly when asked, rather than handing the task back.
Still confirm before prod-visible changes, and note `/api/pricing` is unauthenticated so a pricing
manifest changes advertised prices publicly. The prod TEST gate is skipped because the Test Runner
SP is dev-only — see [[prod-warehouse-deploy-needs-a-token]].
