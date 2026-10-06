---
name: the-cross-charge-exists-for-hygienist-pound-per-hour
description: "The hygienist cross-charge is not about moving money — it is about making the hygienist's pound-per-hour correct, which is why it runs even when the dentist is blank."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-06T14:32:08.169Z
---

The double entry that debits the capitation dentist and credits the hygienist (V210) exists so that
**the hygienist's pound-per-hour comes out right**. Counting the visits is the first half; correcting
whose revenue the visit belongs to is the other half. It is not a payment and nothing settles.

So a cross-charge with **no named dentist on the debit side is fine and should still happen**. On dev
that is 183 visits / £8,975. The owner, 2026-10-06: *"blanks is sort of acceptable. the patient pays
anyway, blank means that the practice gets the revenue, it is still right to cross charge as that
helps get the hygienist pound per hour more correct which is the other half of this equation."*

**How to apply:** do not treat an unresolved dentist on a cross-charge as a data fault to chase, and
do not add a guard that fails the release on one. Judge the feature by whether the hygienist's
£/hour improves, not by whether both legs name a person. Related:
[[capitation-is-an-estimate-not-observed-income]],
[[a-minus-one-fk-hides-under-all-and-kills-under-a-selection]] (the usual case, where a blank FK IS
the bug — this is the exception), [[a-role-filter-blanks-on-my-data]].
