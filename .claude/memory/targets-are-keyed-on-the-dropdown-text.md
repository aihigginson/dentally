---
name: targets-are-keyed-on-the-dropdown-text
description: "The target tables match on [Selection] — the hierarchy drop-down's exact text, figure-space indent included — so the indent is part of the key and a single wrong byte fails silently."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-29T15:59:44.112Z
---

`Gold.Fact_Node_Targets` and `Gold.Aggregate_Period_Targets` are keyed on **`[Selection]`: the
exact string the hierarchy drop-down displays**, indent and all. The app filters
`[Selection] = <the value the user chose>` and nothing is resolved, parsed or joined.

```
Skeleton Group                  <- the client, depth 0, no indent
<FIG><FIG>– North               <- depth 1
<FIG>x4– Manchester             <- depth 2
<FIG>x6– Skeleton Alpha         <- depth 3
```

`<FIG>` is U+2007 FIGURE SPACE, the dash U+2013 EN DASH, matching `index.html`:
`' '.repeat(depth*2) + '– ' + label`.

**Why:** owner's call, 2026-10-29, after rejecting a `Level_Type` + `Level_Key` scheme twice —
*"the table doesn't even NEED to know that one is a region and another an area. it just matches
the text"*. The abstraction was also wrong, not merely abstract: the keys collided (Group `11` vs
Practice `11`, Region `5` vs Area `5`), and Site held the Dentally business key while every report
filters `pk_Practice_Site`, so site targets could never have matched anything.

**How to apply — four ways to break this, all silent:**

1. **The indent is part of the key.** Client 11 has a client, a practice AND a site all called
   "Demonstration Practice"; they differ by no indent, six figure spaces and eight. That is what
   makes a level column unnecessary.
2. **Never re-base the indent for a restricted user.** Depths and the level collapse come from the
   *whole client*, never the visible subset — a North-only user must still see four figure spaces
   on Manchester. Re-basing to two makes every lookup miss.
3. **Build the characters from bytes**, not literals: `CAST(0xE28087 AS VARCHAR(3))`. The file's own
   encoding cannot then alter them. Fabric's collation is `Latin1_General_100_BIN2_UTF8` — binary —
   so a lookalike character returns nothing rather than erroring
   ([[fabric-collation-is-case-sensitive]]).
4. **Both sides must agree on which nodes exist.** A level with one distinct value is not built
   (`/api/filters` and `Gold.usp_Load_Fact_Node_Targets` apply the same test), so Maple gets ONE
   node. A node one side builds and the other does not is a lookup that finds nothing.

`Gold.Dim_Hierarchy_Node` is the single definition of these strings (selection → the sites it
covers) and the **only** table carrying `[Level]` and `[Node_Key]`. Read labels from it rather
than rendering them again anywhere. The keys exist for one question the site sets cannot answer —
*which selection is this practice?* — because a region holding a single practice covers exactly
one tenant, so "shallowest node covering one tenant" returns the region.

`[Role]` replaced `Target_Level`; the practice-wide figure is `'All Roles'`, not `'Practice'`.
Related: [[a-rolling-window-straddles-two-financial-years]],
[[group-target-aggregation-is-unresolved]], [[client-hierarchy-attaches-to-the-site]].
