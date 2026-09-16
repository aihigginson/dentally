---
name: support-logins-are-not-dentally-users
description: Admin/support accounts are inserted into Application_Users by SQL and never appear in any roster built from Gold.Dim_Users.
metadata:
  type: project
---

`admin@analytically.info` and the other `@analytically.info` logins have **no Dentally user
record**. They are inserted straight into `Security.Application_Users` / AppDB
`Input.Application_Users` by hand in SQL.

**Why:** any screen or gate built on a roster is built `FROM Gold.Dim_Users` (the subscriptions
list in `/api/team` is), so those accounts are simply absent from it. On 2026-09-15 this produced
a real bug: the "Stop using Analytically" button was revealed by
`people.some(p => p.is_self && p.is_primary)`, which can never be true for an account with no
roster row — so it stayed hidden from the very person who most needed it. The same accounts were
also being swept up by a `WHERE Client_ID = ?` revocation, which would have locked support out of
a tenant it still had to clean up.

**How to apply:** never identify the signed-in user by looking them up in a Dentally-sourced
roster — compare the UPN directly against whatever table holds the answer (e.g.
`Input.Billing_Contact.Primary_Email`). When a bulk statement acts on "all users of a tenant",
decide deliberately whether support logins are in scope; the established exclusion is
`LOWER(User_UPN) NOT LIKE '%@analytically.info'`, which `Billing.usp_Generate_Invoice_Lines`
already uses to keep them unbilled. Note the primary account holder is chosen by *radio button*
from the Dentally roster, so a support login can never be the recorded primary — gates that only
accept the primary need an explicit support exemption. See [[user-solo-builder-analytically]].
