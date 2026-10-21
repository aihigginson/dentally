---
name: treatment-plan-acceptance-is-unknowable
description: Accepted_At is hardcoded NULL in Silver and absent from Bronze, so no plan can be shown as accepted or declined.
metadata:
  type: reference
---

`Silver.Treatment_Plans.Accepted_At` is written as a literal `NULL` by
`Silver.usp_Load_Treatment_Plans`, with the comment "Accepted_At not in Bronze".
`Bronze.Treatment_Plans` has no such column, because Dentally's treatment-plans endpoint
does not return it. All 71,974 of Maple's plans carry NULL; there is no accepted group to
compare against.

Plans are NOT deleted. The Silver loader does remove rows absent from the extract, but
measured over eight consecutive nights the delete count is 0 every time, so nothing is
quietly vanishing and there is no survivorship bias from removal.

The usable proxies are `Fact_Treatment_Plans.Has_Completed_Item` and
`Private_Treatment_Value_Completed` / `_Outstanding` -- work started, and work still to
do.

**Why:** a practice will ask "do patients reject large treatment plans?". The honest
answer is that the warehouse has no concept of a declined plan, only of work not yet
done. On Maple just 2-6% of plans have no item ever started, while ~35% of presented
value sits outstanding -- which looks like plans being built AS treatment proceeds rather
than quotes presented for acceptance. If that is right, a patient balking at a big plan
never appears as an unstarted plan at all.

**How to apply:** never present a completion-derived figure as an acceptance rate. If
acceptance genuinely matters to a customer, it needs the Dentally API to expose it --
check the endpoint before promising anything. Related:
[[a-dq-rule-built-on-an-absence-is-wrong]], [[read-the-schema-before-querying-it]].
