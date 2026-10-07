---
name: onboarding-is-manual-by-choice
description: Trial signups are provisioned by hand on purpose until there are more than a handful; the sales mailbox is checked hourly.
metadata:
  type: project
---

A trial signup does **not** provision itself. The app captures it in Key Vault
(`onboarding-pending-<env>`) and emails **Sales@Analytically.info** with "Onboarding pending:
<practice>"; a human then runs the onboarding. Both the owner and Grace watch that mailbox, and
the owner checks it hourly.

**Why:** a deliberate choice stated on 2026-10-01, not an oversight — doing it by hand while
volumes are tiny is how the edge cases get learned before they are automated. The stated trigger
for automating is "more than a handful". Do not propose automating it before then.

**How to apply:** the notification path is sound and verified — prod has `APP_ENV=prod`,
`GRAPH_SEND=1`, `ONBOARDING_NOTIFY=Sales@Analytically.info`, and that mailbox exists
("Analytically Sales Team"), sending as `support@analytically.info`. The one weak link is that
`_notify_owner_pending` swallows send failures as non-fatal and only logs
`owner notify failed (non-fatal)` — so a lost email is silent. The signup itself is never lost:
it stays in Key Vault regardless. If a practice signs up and no mail arrives, look there.
Related: [[scale-target-is-100-practices]].
