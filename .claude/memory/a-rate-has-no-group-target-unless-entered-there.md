---
name: a-rate-has-no-group-target-unless-entered-there
description: "Rates only roll down, so a client node shows no rate target at all until one is entered there."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-30T12:29:55.189Z
---

A quantity reaches the client node by rolling UP from the practices; a rate cannot, because rates
roll DOWN only. So a client whose rates have only ever been entered per practice has **no rate
target at the group level at all** — not a wrong one, an absent one.

On DEV (30 Oct 2026) that was fourteen blank tiles on the demo's group view: Diary Fill, DNA Rate,
Cancel %, Short Notice, Book Before Leave, Days to 30min Free, Rebooked %, Rev/Clinical Hr, Avg
Plan, Exam Ratio, Dentist Retention, Email Details, Phone Details, UDA Completion.

**Why:** it reads as "the group has no target" and looks like a bug in the roll-up, but the rule is
working exactly as designed — see [[group-target-aggregation-is-unresolved]].

**How to apply:** when a group customer's rate tiles are blank, do not debug the loader. The fix is
to enter those rates on the "Whole client" tab. The same holds at Region and Area: a rate entered
only below a node never reaches it. Related: [[targets-are-keyed-on-the-dropdown-text]].
