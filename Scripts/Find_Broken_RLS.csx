// ---------------------------------------------------------------------------
// Find_Broken_RLS.csx  --  WHICH security filter expression is broken?
// ---------------------------------------------------------------------------
// Run in Tabular Editor (Advanced Scripting, C# tab) against the model.
//
// ==> DESKTOP SAYS "Some security filter expressions have errors" AND NAMES NOTHING. <== With a
// rule on 40-odd tables that is a needle in a haystack, and the usual cause is invisible: a PBI
// view pins its column list at CREATE time, so a Gold column added AFTER the view was generated
// does not exist in the model, and any rule naming it is silently unbound. The table refreshes
// perfectly well; only the rule is broken.
//
// This prints every role x table expression and checks each 'Table'[Column] reference against
// the model, so the broken one names itself.
//
// Most likely fixes, in order:
//   1. EXEC Meta.usp_Create_Gold_Views   (the view is missing a column the rule needs)
//   2. re-read the table in Desktop      (so the model picks the column back up)
//   3. re-run PBI_Dentally.csx           (so the rule is re-applied from a valid donor)
// ---------------------------------------------------------------------------

var problems = 0;
var checkedCount = 0;

// 'Table Name'[Column Name] or [Column Name] on its own
var qualified = new System.Text.RegularExpressions.Regex(@"'([^']+)'\[([^\]]+)\]");
var bare      = new System.Text.RegularExpressions.Regex(@"(?<!')\[([^\]]+)\]");

foreach (var role in Model.Roles)
{
    foreach (var tbl in Model.Tables)
    {
        var expr = role.RowLevelSecurity[tbl];
        if (string.IsNullOrWhiteSpace(expr)) continue;
        checkedCount++;

        var bad = new System.Collections.Generic.List<string>();

        // qualified references: the table AND the column must both exist
        foreach (System.Text.RegularExpressions.Match m in qualified.Matches(expr))
        {
            var tn = m.Groups[1].Value;
            var cn = m.Groups[2].Value;
            var t2 = Model.Tables.FirstOrDefault(x => x.Name == tn);
            if (t2 == null) { bad.Add("table '" + tn + "' is not in the model"); continue; }
            if (!t2.Columns.Any(c => c.Name == cn) && !t2.Measures.Any(mm => mm.Name == cn))
                bad.Add("'" + tn + "'[" + cn + "] -- that table has no such column");
        }

        // bare references resolve against the table the rule is ON
        foreach (System.Text.RegularExpressions.Match m in bare.Matches(expr))
        {
            var cn = m.Groups[1].Value;
            if (qualified.Matches(expr).Cast<System.Text.RegularExpressions.Match>()
                         .Any(q => q.Groups[2].Value == cn)) continue;   // already seen qualified
            if (!tbl.Columns.Any(c => c.Name == cn) && !tbl.Measures.Any(mm => mm.Name == cn))
                bad.Add("[" + cn + "] -- '" + tbl.Name + "' has no such column");
        }

        if (bad.Count > 0)
        {
            problems++;
            Info("BROKEN  role '" + role.Name + "' on '" + tbl.Name + "':\n    "
                 + string.Join("\n    ", bad) + "\n  expression:\n    " + expr.Replace("\n", "\n    "));
        }
    }
}

// A table that is tenant-bearing but carries NO rule is the other way to leak, and this message
// is not raised by Desktop at all -- it is not an error, just an open door.
var unfiltered = new System.Collections.Generic.List<string>();
foreach (var tbl in Model.Tables)
{
    var bears = tbl.Columns.Any(c => c.Name == "Tenant ID" || c.Name == "Client ID");
    if (!bears) continue;
    var anyRule = Model.Roles.Any(r => !string.IsNullOrWhiteSpace(r.RowLevelSecurity[tbl]));
    if (!anyRule) unfiltered.Add(tbl.Name);
}

Info("Checked " + checkedCount + " role x table expression(s). "
     + (problems == 0 ? "NONE are broken." : problems + " BROKEN -- see above.")
     + (unfiltered.Count > 0
        ? "\n\nALSO UNFILTERED (carries Tenant ID or Client ID but no rule in any role):\n  "
          + string.Join("\n  ", unfiltered)
        : "\n\nEvery tenant- or client-bearing table carries a rule."));
