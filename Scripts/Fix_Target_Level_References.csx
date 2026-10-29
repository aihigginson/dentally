// ---------------------------------------------------------------------------
// Fix_Target_Level_References.csx  --  repair measures left on the old target column
// ---------------------------------------------------------------------------
// Run in Tabular Editor (Advanced Scripting, C# tab), then SAVE the model.
//
// Gold.Aggregate_Period_Targets was re-keyed on 2026-10-29:
//     [Target Level]  ->  [Role]
//     "Practice"      ->  "All Roles"      (the practice-wide figure)
// because [Target Level] held 'Hygienist', which is no kind of hierarchy level.
//
// PBI_Dentally.csx regenerates every measure it owns, so normally running that is the fix. This
// exists for when it is not:
//   * Tabular Editor ran a STALE copy of the .csx from an already-open tab,
//   * the script threw before reaching the Clinical block, or
//   * the measure is HAND-MADE on a fact table and the csx does not own it at all.
//
// It walks EVERY table's measures, not just '_Measures', which is the point -- the csx owns only
// that one, and fact tables carry hand-written measures reports bind to.
//
// Safe to run twice: it only touches measures that still contain the old column reference, and
// reports anything it could not fully resolve rather than guessing.
// ---------------------------------------------------------------------------

var OLD_COL = "'Aggregate Period Targets'[Target Level]";
var NEW_COL = "'Aggregate Period Targets'[Role]";

int fixedCount = 0, residual = 0;
var touched  = new System.Collections.Generic.List<string>();
var leftover = new System.Collections.Generic.List<string>();

foreach (var tbl in Model.Tables)
{
    foreach (var m in tbl.Measures.ToList())
    {
        var e = m.Expression;
        if (e == null || e.IndexOf(OLD_COL) < 0) continue;

        var before = e;

        // Order matters: the explicit practice-wide filter first, or the generic column swap
        // below would strip the context that identifies it.
        e = e.Replace(OLD_COL + " = \"Practice\"", NEW_COL + " = \"All Roles\"");
        e = e.Replace(OLD_COL, NEW_COL);

        // the role in context; 'All Roles' is what the practice-wide figure is called now
        e = e.Replace("COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), \"Practice\")",
                      "COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), \"All Roles\")");

        // the FTE multiplier: a practice-wide target is already whole, a per-FTE one is scaled
        e = e.Replace("IF(lvl = \"Practice\"", "IF(lvl = \"All Roles\"");

        if (e == before) continue;

        m.Expression = e;
        fixedCount++;
        touched.Add("'" + tbl.Name + "'[" + m.Name + "]");

        // A "Practice" left in a measure that referenced the old column is suspicious: it may be
        // another spelling of the practice-wide figure that these patterns did not catch.
        if (e.IndexOf("\"Practice\"") >= 0)
        {
            residual++;
            leftover.Add("'" + tbl.Name + "'[" + m.Name + "] still contains \"Practice\" -- check by hand");
        }
    }
}

// Anything still naming the dropped column means a pattern above did not match it.
var stillBroken = new System.Collections.Generic.List<string>();
foreach (var tbl in Model.Tables)
    foreach (var m in tbl.Measures)
        if (m.Expression != null && m.Expression.IndexOf("[Target Level]") >= 0)
            stillBroken.Add("'" + tbl.Name + "'[" + m.Name + "]");

var report = new System.Text.StringBuilder();
report.AppendLine(fixedCount + " measure(s) repaired.");
if (fixedCount > 0)
{
    report.AppendLine();
    report.AppendLine("A non-zero count here means the model was still holding the OLD generated");
    report.AppendLine("DAX -- so PBI_Dentally.csx either did not run, ran from a stale tab, or was");
    report.AppendLine("not saved. Worth knowing which, because the next change will do it again.");
    report.AppendLine();
    foreach (var s in touched.Take(40)) report.AppendLine("  " + s);
    if (touched.Count > 40) report.AppendLine("  ... and " + (touched.Count - 40) + " more");
}
if (leftover.Count > 0)
{
    report.AppendLine();
    report.AppendLine("CHECK BY HAND:");
    foreach (var s in leftover) report.AppendLine("  " + s);
}
report.AppendLine();
report.AppendLine(stillBroken.Count == 0
    ? "Nothing references [Target Level] any more."
    : stillBroken.Count + " measure(s) STILL reference [Target Level]:\n  "
      + string.Join("\n  ", stillBroken));
report.AppendLine();
report.AppendLine("Now SAVE the model -- the repair is in memory until you do.");

Info(report.ToString());
