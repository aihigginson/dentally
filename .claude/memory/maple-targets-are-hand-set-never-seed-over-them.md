---
name: maple-targets-are-hand-set-never-seed-over-them
description: "All 334 of Maple's targets were set by hand with Craig; the onboarding seeder has never written a row anywhere, so there is nothing to \"re-seed\" and --replace must never be used on tenant 100."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-02T09:07:28.149Z
---

Checked on 2026-10-02: every target row for tenant 100 carries
`Updated_By = 'admin@analytically.info'` — 334 rows across FY2025, FY2026 and FY2027, at Practice
level plus Associate, Associate Specialist, Hygienist, Implantologist and Principal.
**`Updated_By = 'Seed_Targets_From_Actuals'` appears nowhere, in any environment.**

So `Scripts/Seed_Targets_From_Actuals.py` has never been applied. Its scope is the NEXT practice to
onboard, not Maple. **Never run it with `--apply --replace` against tenant 100** — that would
replace figures the owner agreed with the practice with crude no-uplift derivations. The script's
own refusal ("pass --replace only if you are certain those are not real targets someone set") is
the control, and it is correct.

**Why:** I spent a morning repeatedly recommending a "re-seed" of Maple's targets after V201/V202
corrected the actuals basis, and wrote into the V202 commit message that two metrics "had already
been seeded as onboarding targets". They had not — those figures came from a DRY RUN I had printed
and then treated as persisted state. Acting on my own recommendation would have overwritten a live
customer's targets.

**How to apply:** before proposing anything that writes targets, query `Updated_By` first — it
distinguishes hand-set from generated in one column. More generally: a dry run's output is not
state. Do not carry a printed figure forward as though it were in the database, and do not build a
follow-up task on it without re-reading the table. Related:
[[dev-targets-are-dummy-prod-targets-are-real]], [[never-deploy-an-input-table-in-a-release]],
[[onboarding-is-manual-by-choice]].
