---
name: grace-is-an-affiliate-not-staff
description: "Grace Wood holds an @analytically.info mailbox but is a sole-trader AFFILIATE, not an employee — the domain does not mean staff."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-05T16:01:45.328Z
---

`grace@analytically.info` is a **sole trader affiliate**, not an employee. She uses one of our
mailboxes deliberately, so outreach to practices reads as coming from Analytically. Created as
prod affiliate ID 1 on 2026-10-05 at the standard 20%.

**Why this is worth writing down:** the address says staff and the person is not, so I guessed
wrong and argued against putting her in prod — twice — on the grounds that she was "one of your own
mailboxes" and would be test data in live commercial records. She is a real commercial
relationship, and a lifetime one (see [[first-reseller-is-an-informal-individual]]).

**How to apply:** `@analytically.info` identifies a MAILBOX, never a role. Note the code relies on
that domain in two places and both remain correct for their own reasons, so do NOT "fix" them to
account for Grace:

* `Gold.usp_Load_Dim_Client` excludes `%@analytically.info` from `Users_Provisioned` — right,
  because a practice should not be billed or judged on seats we hold in their tenant.
* The sales monitor's `Is_Vendor` routes that usage to the vendor's own client row — also right,
  because when Grace opens a practice's reports she IS acting as Analytically, which is the whole
  point of giving her the address.

So the domain test is correct for ACCESS and wrong for EMPLOYMENT. Ask rather than infer which one
a question is about. Related: [[support-logins-are-not-dentally-users]],
[[my-data-is-unfiltered-for-vendor-accounts-by-design]].
