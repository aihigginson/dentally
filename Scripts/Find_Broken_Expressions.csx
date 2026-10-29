// ---------------------------------------------------------------------------
// Find_Broken_Expressions.csx  --  WHERE is the broken reference, exactly?
// ---------------------------------------------------------------------------
// Run in Tabular Editor (Advanced Scripting, C# tab). Reports only; changes nothing.
//
// ==> DESKTOP SAYS "152 objects with errors" AND A REPAIR THAT WALKED MEASURES FOUND NOTHING. <==
// That contradiction has only two honest explanations, and this tells you which:
//
//   1. The reference is NOT in a measure. Expressions also live in calculated columns,
//      calculated tables, calculation items, KPI status/trend/target expressions, detail-rows
//      expressions and RLS filters. A measure-only sweep reports 0 and is not wrong, just blind.
//
//   2. The script ran against a DIFFERENT model from the one showing the errors -- Tabular
//      Editor connected over XMLA to the published dataset while Desktop holds its own local
//      copy. Both are "the model" and only one of them has the problem.
//
// The header printed below settles (2): if the table/measure counts do not match what Desktop
// shows, the connection is the problem and nothing in this report matters.
//
// Edit NEEDLE if you are chasing something else.
// ---------------------------------------------------------------------------

var NEEDLE = "[Target Level]";

var hits = new System.Collections.Generic.List<string>();
void Hit(string kind, string where, string expr)
{
    if (string.IsNullOrEmpty(expr) || expr.IndexOf(NEEDLE) < 0) return;
    var i = expr.IndexOf(NEEDLE);
    var from = System.Math.Max(0, i - 60);
    var snip = expr.Substring(from, System.Math.Min(expr.Length - from, 150)).Replace("\n", " ");
    hits.Add(kind + "  " + where + "\n        ..." + snip + "...");
}

int measures = 0, calcCols = 0, calcTables = 0, calcItems = 0, kpis = 0, rules = 0, detail = 0;

foreach (var t in Model.Tables)
{
    // calculated TABLE: its partition carries the DAX
    try {
        var ct = t as CalculatedTable;
        if (ct != null) { calcTables++; Hit("CALC TABLE ", "'" + t.Name + "'", ct.Expression); }
    } catch { }

    foreach (var c in t.Columns)
    {
        try {
            var cc = c as CalculatedColumn;
            if (cc != null) { calcCols++; Hit("CALC COLUMN", "'" + t.Name + "'[" + c.Name + "]", cc.Expression); }
        } catch { }
    }

    foreach (var m in t.Measures)
    {
        measures++;
        Hit("MEASURE    ", "'" + t.Name + "'[" + m.Name + "]", m.Expression);
        try { if (!string.IsNullOrEmpty(m.DetailRowsExpression)) { detail++; Hit("DETAIL ROWS", "'" + t.Name + "'[" + m.Name + "]", m.DetailRowsExpression); } } catch { }
        try {
            if (m.KPI != null)
            {
                kpis++;
                Hit("KPI STATUS ", "'" + t.Name + "'[" + m.Name + "]", m.KPI.StatusExpression);
                Hit("KPI TARGET ", "'" + t.Name + "'[" + m.Name + "]", m.KPI.TargetExpression);
                Hit("KPI TREND  ", "'" + t.Name + "'[" + m.Name + "]", m.KPI.TrendExpression);
            }
        } catch { }
    }

    try { if (!string.IsNullOrEmpty(t.DefaultDetailRowsExpression)) Hit("DETAIL ROWS", "'" + t.Name + "' (table default)", t.DefaultDetailRowsExpression); } catch { }
}

// calculation groups / items
try {
    foreach (var cg in Model.CalculationGroups)
        foreach (var ci in cg.CalculationItems)
        {
            calcItems++;
            Hit("CALC ITEM  ", "'" + cg.Name + "'[" + ci.Name + "]", ci.Expression);
            try { Hit("CALC ITEM FMT", "'" + cg.Name + "'[" + ci.Name + "]", ci.FormatStringExpression); } catch { }
        }
} catch { }

// RLS
foreach (var role in Model.Roles)
    foreach (var t in Model.Tables)
    {
        var e = role.RowLevelSecurity[t];
        if (string.IsNullOrWhiteSpace(e)) continue;
        rules++;
        Hit("RLS RULE   ", "role '" + role.Name + "' on '" + t.Name + "'", e);
    }

var r = new System.Text.StringBuilder();
r.AppendLine("MODEL: " + Model.Database.Name + "   (" + Model.Tables.Count + " tables)");
r.AppendLine("If that name or table count is not the model Desktop is showing you, STOP -- the");
r.AppendLine("connection is the problem, not the expressions.");
r.AppendLine();
r.AppendLine("Scanned: " + measures + " measures, " + calcCols + " calculated columns, "
             + calcTables + " calculated tables,");
r.AppendLine("         " + calcItems + " calculation items, " + kpis + " KPIs, "
             + detail + " detail-rows expressions, " + rules + " RLS rules.");
r.AppendLine();
r.AppendLine("Does 'Aggregate Period Targets' have a [Role] column? "
    + (Model.Tables.Contains("Aggregate Period Targets")
        ? (Model.Tables["Aggregate Period Targets"].Columns.Any(c => c.Name == "Role") ? "YES" : "NO -- re-read the table")
        : "the table is not in the model at all"));
r.AppendLine();
r.AppendLine(hits.Count == 0
    ? "NOTHING in this model contains " + NEEDLE + ".\n\nSo the errors Desktop is showing belong to a different model, or its error list is\nstale -- close and reopen the file, or refresh, before chasing this further."
    : hits.Count + " object(s) contain " + NEEDLE + ":\n\n  " + string.Join("\n  ", hits.Take(60))
      + (hits.Count > 60 ? "\n  ... and " + (hits.Count - 60) + " more" : ""));

Info(r.ToString());
