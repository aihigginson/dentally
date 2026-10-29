---
name: group-target-aggregation-is-unresolved
description: "RESOLVED 2026-10-29 — how targets combine across the hierarchy is now a Rolls_Up column on Config.Metric_Definitions, resolved in the node loader, not in DAX."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-29T12:42:35.651Z
---

**RESOLVED.** Kept because the shape it predicted turned out to be the shape built, and because
the superseded behaviour explains old numbers.

How a target combines across the hierarchy is now `Config.Metric_Definitions.Rolls_Up` (BIT, 27
metrics down / 17 up), resolved in `Gold.usp_Load_Fact_Node_Targets`: quantities roll **up** the
tree child-to-parent in four passes, rates roll **down** parent-to-child in four. An entered
figure at any level is never overwritten, so it stops the roll and becomes the truth for
everything above (or below) it. That is the "`Group_Aggregation` column beside `Target_Type`,
resolved in the loader, not more DAX" this note guessed at — so the guess is worth trusting next
time the same question comes up elsewhere.

**What it used to do** (and why an archived figure may not reconstruct): cumulative SUMmed across
practices, while **rate** and **point_in_time** took MAX — whichever practice aimed highest. The
rate/point-in-time behaviour predates V196; V196 only restored SUM for cumulative after briefly
making it MAX too.

**Still deliberately unresolved:** a rate rolling *down* means every child inherits the parent's
figure unchanged. A group setting 85% diary fill gives all its practices 85%, not a weighted
split. That is intended — a rate cannot be derived upward from children, so the only honest
direction is down — but it does mean a parent rate is an instruction, not a summary.

**Partial children are wrong, and that is accepted:** if A+B+C should equal D, entering only A+B
gives a smaller D. The owner's call on 2026-10-29: fine and visible, not a bug to guard.

Related: [[verify-aggregation-changes-on-two-tenants]],
[[a-rolling-window-straddles-two-financial-years]], [[financial-years-differ-per-tenant]].
