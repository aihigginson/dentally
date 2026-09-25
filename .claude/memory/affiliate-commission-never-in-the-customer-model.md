---
name: affiliate-commission-never-in-the-customer-model
description: Affiliate commission is vendor money and is not imported into the PBI Dentally model. It still follows the medallion build like everything else - Gold tables with generated PBI views.
metadata:
  type: project
---

**Affiliate commission is not imported into the `PBI Dentally` semantic model.** It is vendor
money -- what Analytically pays a referral partner for introducing a practice -- so a practice
owner must never see what an introducer earns from them, and an affiliate must never see other
practices. It gets its own small standalone model in the Fabric workspace.

**That is a decision about which tables a model imports. It is NOT a reason to build the data
differently.** On 2026-09-24 I built it as two ad-hoc `Billing.vw_*` views and added a guard
script that failed if anything affiliate-shaped appeared in the `PBI` schema. Both were wrong, and
the user said so: *"You didnt need to hardwire a gate... You've not matched the medalian
architecture... I won't add it to the PBI Dentally model but that doesnt mean it should diverge
from all the build principals."*

The guard was worse than redundant: `Meta.usp_Create_Gold_Views` generates a `PBI.*` view for
EVERY Gold object, so the guard would have failed the correct architecture the moment
`Gold.Dim_Affiliates` existed.

**How to apply:** build it like everything else -- Gold tables with `Gold.usp_Load_*` procs,
registered in `Audit.Process_Config` / `Process_Dependency`, with `PBI.*` views generated
automatically. `Billing.*` feeding Gold is normal: 13 Gold loads already read the owner-curated
`Input` schema the same way. The control on who sees it is which tables get imported into which
semantic model, exercised by the owner -- not a script, and not a different build pattern.

See [[sql-files-are-mostly-utf8-not-utf16]] for the encoding convention these files follow.
