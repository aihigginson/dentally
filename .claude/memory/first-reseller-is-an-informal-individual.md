---
name: first-reseller-is-an-informal-individual
description: "The first reseller is a non-VAT individual on an informal arrangement; the self-bill UI can wait, and the free month means no commission for at least a month."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-05T12:40:11.409Z
---

2026-10-05: first reseller interest. An **individual, not VAT registered, informal** — so the
heavyweight self-billing machinery is not on the critical path. Agreed with the owner: work on it
over the following weeks, do not build it in a hurry.

**Onboarding needs no code.** Admin panel → Affiliate → their email + rate (standard 20%) creates
the affiliate; link each practice as they introduce it. Commission is explicitly NOT retrospective.

**The free month means nothing is payable for at least a month**, and this is automatic — not
something to remember. `Billing.usp_Generate_Invoice_Lines`: `bill_start = MAX(user's first
billable date, Paid_From)`, "nothing bills before it", and commission is
`ROUND(line.Value × rate, 2)` of each INVOICED line. No invoice during the trial ⇒ no commission.
So a signup today earns £0 this month, and nothing is ever paid on a trial that does not convert.

**==> AN AFFILIATE RELATIONSHIP IS FOR LIFE, SO THERE IS NO RETIRE. <==** Settled with the owner
2026-10-05: a partner earns commission for as long as the clients they introduced keep paying. There
is no archive or inactive flag on `Billing.Affiliate` and none is wanted -- "more than a handful of
affiliates" is the only thing that would change that, and the owner will say so. DELETE is therefore
only ever for undoing a mistake, which is exactly what the guards enforce: an affiliate with any
assigned practice or any commission on an invoice line cannot be removed. Do not propose archiving
again.

**Possible, not planned:** the owner raised on 2026-10-05 that Grace might one day introduce
AFFILIATES rather than practices, each earning 20% — a second tier. Explicitly "for another day",
so do not build it or design for it. Just know the shape today cannot express it:
`Billing.Account_Billing` carries ONE `Affiliate_ID`, so commission has a single recipient per
practice. Avoid changes that would make a second tier harder, and otherwise leave it alone.

**Still manual, and fine for now:** the V185 self-bill columns (`VAT_Number`, `Is_VAT_Registered`,
`Self_Bill_Agreed_On`, `Address`, `Bank_*`) have NO UI — `Can_Self_Bill` stays false until they are
set by hand; payouts are hand-inserted into `Billing.Affiliate_Payout`. There is also no partner
sign-up form, login or referral code anywhere, by design — `partners.html` is an information page
whose CTAs are `mailto:partners@analytically.info`.

**How to apply:** partner earnings maths uses **£150/month as the average practice bill** (priced
per user; £60 is only the entry full-access seat — do not quote £60 as the bill). 20% of that is
£360/practice/year. The live page said "ten practices is a five-figure annual income"; it is
£3,600, and five figures needs ~28 practices. Fixed 2026-10-05 — the audience is the NASDAL
directory of 33 dental accountancy firms, who check arithmetic for a living. Related:
[[affiliate-commission-never-in-the-customer-model]], [[onboarding-is-manual-by-choice]].
