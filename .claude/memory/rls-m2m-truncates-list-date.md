---
name: rls-m2m-truncates-list-date
description: RLS on List Date Grouping silently truncates List Date, because their relationship is many-to-many and so cross-filters security both ways.
metadata:
  type: project
---

The model's only many-to-many relationship is `List Date`[pk Date] <-> `List Date
Grouping`[fk Date] (`toCardinality: many` with `fromCardinality` defaulting to many;
relationship GUID `53691e5c-3cf2-e98c-e5c3-32e1ff6d727d`, present in BOTH dev and prod).
M2M relationships are *limited*: they cross-filter in both directions, security filters
included, and they have no blank-row rescue for unmatched keys.

`List Date Grouping` carries an RLS rule. So the moment RLS is active, its filter
propagates back up into `List Date`, cutting the date dimension to only the dates that
appear in the grouping table -- and with it every fact row on an uncovered date.
`Gold.Dim_Date_Grouping` covers `2021-01-01 .. <last build date>` and emits **no future
rows at all**, so on 2026-09-16 that hid 8,993 appointments in dev and 8,982 in prod
(~5% of the fact table), every one of them future-dated. Invisible in the app, visible
in Desktop -- because Desktop applies no RLS unless you use View as.

**Why:** the symptom looks nothing like its cause. The rule text is innocent (plain
`Tenant ID IN (...) || Tenant ID = -1` on all 43 tables), every dimension row the missing
facts reference is tenant-correct, and the loss tracks *date* while no rule mentions
dates. Reasoning from the role definition therefore produces confident wrong answers --
it did here, repeatedly, and burned most of a session. Note `List Date Unconstrained`
already exists in the model as a workaround for exactly this, so it had been hit before
and papered over.

**How to apply:** when rows are present in Desktop but missing in the embedded app,
suspect RLS *propagation*, not the rule predicates -- and reproduce it rather than reading
the TMDL. `executeQueries` cannot: `impersonatedUserName` is silently ignored for the
dataset owner (control: `COUNTROWS('Application Users')` returns all rows either way where
the role would return 1), and ADOMD over XMLA rejected every auth form tried. Power BI
Desktop's **View as** plus deactivating one relationship at a time in Model view is what
actually found this.

**The fix, confirmed working 2026-09-16:** on the Edit relationship dialog, Cross-filter
direction = **Both**, and "Apply security filter in both directions" left **unchecked**.
Cardinality stays Many to many and the From/To orientation is untouched
(From `List Date Grouping`[fk Date] -> To `List Date`[pk Date]). Those are two independent
knobs and both are needed: report filters must travel Date Grouping -> List Date for the
period drop-down, security filters must not. Setting Cross-filter to Single fixes the row
loss but silently kills the drop-down -- every grouping then returns everything.

Relationships and joins are the user's to own; do not script model relationships. The only
C# run here is `Fabric/PBI_Dentally.csx`, and it is for DAX measures only.
See [[user-solo-builder-analytically]].
