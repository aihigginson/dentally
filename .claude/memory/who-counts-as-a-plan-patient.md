---
name: who-counts-as-a-plan-patient
description: "Plan membership = Input.Plan_Capitation_Rate, not Fact_Plan_Spell: a spell needs an attended free exam, so members who never come in have none."
metadata:
  type: reference
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-07T13:53:52.318Z
---

Three candidate definitions, measured on prod (tenant 100, 07/10/2026):

* **`Input.Plan_Capitation_Rate`** — a patient whose `Payment_Plan_ID` is in the owner-curated rate
  table. **1,410 active patients.** This is the one to use.
* `Gold.Fact_Plan_Spell` where `Is_Open = 1` — **1,374**.
* Capitation billed in the last 3 months — 1,386.
* `Standard_Payment_Plan IS NOT NULL` — **7,036**, and wrong: "Private", "NHS", "Referral" and
  "IRH Fees" are payment plans too. Only the eight `Denplan%` tiers are capitation.

**Why the rate table wins:** a spell is reconstructed from *attended* free exams
([[capitation-is-an-estimate-not-observed-income]]), so a member who has never been through the
door has no spell. The 36-patient gap is not noise — for any question about non-attendance those
36 are the answer, and a spell-based population hides them. The rate table is also what
`Gold.Fact_Revenue_Capitation` bills against, so a check built on it counts the same people as the
income it protects, and it names no plan per tenant.

**How to apply:**

```sql
EXISTS (SELECT 1 FROM Input.Plan_Capitation_Rate r
        WHERE r.Tenant_ID = p.Tenant_ID AND r.Payment_Plan_ID = p.Payment_Plan_ID)
```

Related: [[read-the-schema-before-querying-it]], [[never-deploy-an-input-table-in-a-release]] — the
rate table is owner-curated, so read it, never ship it.
