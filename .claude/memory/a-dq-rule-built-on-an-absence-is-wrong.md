---
name: a-dq-rule-built-on-an-absence-is-wrong
description: "A data-quality rule that fires on something NOT having happened gets answered by ordinary practice life — a staff handover, a booking. Require positive evidence, and check the forward diary."
metadata:
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-07T18:49:10.684Z
---

V216's mis-allocation check asked *"has the allocated dentist seen this patient?"* and read **no**
as evidence the allocation was wrong. The owner caught it immediately: *"Ian Hunt is no longer
active and David has taken over his list. It is incorrect to flag these as with the wrong
dentist."* A departed dentist's reassigned list answers that absence in full — every patient on it
says no while being correctly allocated to the successor. **28 of 56 rows were the handover.**

Then: *"it needs to look at the forward diary... You cant be inactive if you have a forward
appointment."* A booking is the practice already putting the thing right.

**Why:** a practice is a going concern. Staff leave and lists move; patients get booked. Any rule
whose trigger is "X did not happen" will be satisfied in bulk by events that are not faults at all,
and it fires hardest right after a handover — the worst possible moment to hand someone a list of
47 wrong names. 47 became 7.

**How to apply:** when writing a check, ask what POSITIVE evidence the finding requires and test
for that instead of its absence — here, "saw an ACTIVE dentist who is not the allocated one", which
killed the handover and the hygienist-only attenders in one predicate. Then ask whether the diary
already answers it: `PAT_DORMANT` has always excluded booked patients and the new checks should
have copied it rather than reasoning that the "Next in" column made it visible. A worklist that
lists what is already fixed is a worklist people stop working.

Also: never name an inactive practitioner in a detail row — it points the reader at someone who has
gone. Related: [[who-counts-as-a-plan-patient]], [[read-the-schema-before-querying-it]].
