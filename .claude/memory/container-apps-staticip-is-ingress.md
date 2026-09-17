---
name: container-apps-staticip-is-ingress
description: A Container Apps environment's staticIp is its INBOUND address; egress comes from a rotating Azure pool, so no IP-based firewall can allow it.
metadata:
  type: reference
---

`az containerapp env show --query properties.staticIp` on `cae-analytically` returns
`20.90.228.103`. That is the **ingress** address. Outbound traffic leaves from a rotating pool of
Azure IPs — an `appdb-sync` job execution was observed egressing from `4.159.25.18`.

The environment is **Consumption-only with `vnetConfiguration: null`**, so there is no NAT gateway
and no stable egress IP available, and VNet integration cannot be added to an existing Container
Apps environment — it requires building a new one and recreating both container apps.

**Why:** on 2026-09-17 I whitelisted `staticIp` on the new Azure SQL server and asserted the
migration needed "no firewall change". The job then failed with
`Client with IP address '4.159.25.18' is not allowed to access the server`, and the web app would
have hit the same wall at cutover — it only reaches Fabric because Fabric endpoints have no IP
firewall at all.

**How to apply:** for anything in Container Apps reaching an IP-firewalled Azure resource, the
answer is the `AllowAllWindowsAzureIps` (0.0.0.0) rule. Say plainly what it does and does not do:
it widens network *reachability* to any Azure-hosted resource but grants **no access** — with
Entra-only auth a caller still needs a token for a principal holding a database user. The security
boundary is authentication, not IP. Do not claim a Container Apps workload has a fixed outbound
address. See [[rls-m2m-truncates-list-date]].
