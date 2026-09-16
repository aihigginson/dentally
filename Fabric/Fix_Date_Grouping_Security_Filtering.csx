// ---------------------------------------------------------------------------
// Fix_Date_Grouping_Security_Filtering.csx
// ---------------------------------------------------------------------------
// One-off model fix. Run once per environment via Tabular Editor, then publish.
//
// PROBLEM
// 'List Date'[pk Date] <-> 'List Date Grouping'[fk Date] is many-to-many, which is
// intended: Date Grouping is a tenant-specific financial calendar plus the date list
// behind the period drop-down, and in normal use the tenant + period-name filters
// collapse it to one row per date, so it filters List Date. That is correct.
//
// But RLS applies the tenant filter UNCONDITIONALLY, with no period selected. Because
// an M2M relationship is a limited relationship, its security filtering is bidirectional
// by default -- so that lone tenant filter propagates into List Date and truncates the
// calendar to whatever dates the tenant's grouping rows happen to cover.
// Gold.Dim_Date_Grouping stops at the last build date and emits no future rows, so on
// 2026-09-16 this hid 8,993 appointments in dev / 8,982 in prod -- every future-dated
// row -- from every app user. Invisible in the app, visible in Desktop, because Desktop
// applies no RLS unless you use View as.
//
// FIX
// Leave the cardinality and cross filter direction exactly as they are: normal report
// filters must still flow Date Grouping -> List Date, or the period drop-down stops
// working. Only stop SECURITY filters flowing that way. OneDirection confines security
// propagation to from -> to (List Date -> List Date Grouping), which is the direction
// RLS never needed.
//
// The RLS rule on 'List Date Grouping' is untouched, so a user still sees only their own
// tenant's calendar rows in the drop-down; only the propagation into the shared date
// dimension is suppressed.
// ---------------------------------------------------------------------------

var rel = Model.Relationships.OfType<SingleColumnRelationship>().FirstOrDefault(r =>
        r.FromTable.Name == "List Date"          && r.FromColumn.Name == "pk Date" &&
        r.ToTable.Name   == "List Date Grouping" && r.ToColumn.Name   == "fk Date");

if (rel == null)
    throw new Exception("List Date -> List Date Grouping relationship not found.");

Info(string.Format(
    "before: cardinality {0}:{1}, crossFilter {2}, securityFilter {3}",
    rel.FromCardinality, rel.ToCardinality,
    rel.CrossFilteringBehavior, rel.SecurityFilteringBehavior));

rel.SecurityFilteringBehavior = SecurityFilteringBehavior.OneDirection;

Info(string.Format(
    "after : cardinality {0}:{1}, crossFilter {2}, securityFilter {3}",
    rel.FromCardinality, rel.ToCardinality,
    rel.CrossFilteringBehavior, rel.SecurityFilteringBehavior));
