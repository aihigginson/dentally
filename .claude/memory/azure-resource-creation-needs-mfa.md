---
name: azure-resource-creation-needs-mfa
description: "Azure refuses CREATE/UPDATE/DELETE of resources from a non-MFA az token (RequestDisallowedByAzure) even for a subscription Owner; reads and ACR builds still work."
metadata:
  type: project
---

`az containerapp job create` failed with:

    (RequestDisallowedByAzure) ... you tried to create, update or delete Azure resources
    without authenticating through MFA.

The account is **Owner on the subscription** -- this is not a permissions problem and no
role assignment fixes it. A tenant policy requires the token itself to carry an MFA claim.

**What still works without MFA:** every read (`az resource show`, `az role assignment list`,
`az containerapp job execution list`), and `az acr build`, which pushed an image fine. So a
session can look entirely healthy right up to the moment it tries to create something.

**Why:** it reads like an access problem and invites a wasted hunt through role assignments.
It is a property of the TOKEN, not the identity.

**How to apply:** ARM writes need the owner to run `az login` interactively first. Scripted
resource creation should therefore be handed over as a script to run, not attempted from a
background session. Warehouse deploys are unaffected -- they use a delegated database token,
not ARM. Related: [[prod-warehouse-deploy-from-the-laptop]],
[[prod-write-blocks-are-auto-mode-not-permissions]].
