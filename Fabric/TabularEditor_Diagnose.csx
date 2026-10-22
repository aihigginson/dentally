// Read-only diagnostic. Changes nothing, saves nothing.
//
// The measures exist, so the question is now whether their DEFINITIONS are this afternoon's
// or an older copy -- and whether the radar is bound to the measures that changed. A measure
// can be present and still hold yesterday's DAX.
var show = new[] { "Y1 Avg £", "%Delivered", "%Attrition", "First Visit Proposed",
                   "Year One Completed",
                   "Spider PB Val Year One per Patient",
                   "Spider PB Val %Delivered",
                   "Spider PB Val Patients At Risk" };

var sb = new System.Text.StringBuilder();
foreach (var n in show)
{
    var m = Model.Tables.SelectMany(t => t.Measures).FirstOrDefault(x => x.Name == n);
    sb.AppendLine("=== " + n + (m == null ? "   *** NOT FOUND ***" : "   [" + m.Table.Name + "]"));
    if (m != null)
    {
        var dax = m.Expression.Replace("\r", " ").Replace("\n", " ");
        while (dax.Contains("  ")) dax = dax.Replace("  ", " ");
        sb.AppendLine("    " + (dax.Length > 230 ? dax.Substring(0, 230) + " ..." : dax));
    }
    sb.AppendLine();
}

// The three tells, in plain language.
var y1 = Model.Tables.SelectMany(t => t.Measures).FirstOrDefault(x => x.Name == "Y1 Avg £");
var dl = Model.Tables.SelectMany(t => t.Measures).FirstOrDefault(x => x.Name == "%Delivered");
var at = Model.Tables.SelectMany(t => t.Measures).FirstOrDefault(x => x.Name == "%Attrition");
sb.AppendLine("VERDICT");
sb.AppendLine("  Y1 Avg uses Completed : "
    + (y1 != null && y1.Expression.Contains("Year One Completed") ? "YES (current)" : "NO (stale)"));
sb.AppendLine("  First Visit Proposed is windowed in %Delivered's denominator : "
    + (dl != null && dl.Expression.Contains("First Visit Proposed") ? "check the measure above" : "?"));
sb.AppendLine("  %Attrition uses the outcome denominator : "
    + (at != null && at.Expression.Contains("Expected") ? "YES (current)" : "NO (stale)"));
sb.AppendLine();
sb.AppendLine("If these say current, the model is right and the REPORT is reading an older");
sb.AppendLine("published copy -- save in Tabular Editor, then publish, then refresh the report.");

Info(sb.ToString());
