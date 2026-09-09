---
name: user-solo-builder-analytically
description: Solo builder, data/BI engineer, and Microsoft 365 tenant admin for the Analytically product.
metadata:
  type: user
---

The user builds **Analytically** single-handedly — a multi-tenant SaaS analytics product
for dental practices on Dentally (Fabric medallion warehouse + embedded Power BI + Flask
app). They are the data/BI engineer, the product owner, and the Global Admin of the
`analytically.info` Microsoft 365 tenant, so infrastructure, compliance and account
administration all land on them alongside the build.

Practical consequences: there is no second pair of hands to catch a mistake, and (as of
2026-09-07) `Admin@Analytically.info` appeared to be the only Global Admin — a lockout
risk worth remembering. They work on Windows with the repo inside OneDrive, and prefer
being walked through unfamiliar admin UIs step by step with the exact click paths.
See [[back-up-claude-state-on-machine-moves]].
