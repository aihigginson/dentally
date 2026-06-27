// TabularEditor_CompareActuals.csx
// -----------------------------------------------------------------------------
// A/B harness for switching the KPI-card ACTUALS onto the materialised
// Gold.Fact_Metric_Actuals (exposed as the model table '_Metric Actuals').
//
// Adds, per Tier-1 metric, the REAL production measure ("<Metric> New") that
// reads '_Metric Actuals' with the SAME FY + site/practitioner grain resolution
// as the existing card measures (tDaily / tEff), plus a delta ("<Metric> Delta")
// = existing - new, so 0 means they tie out. Put New beside the existing actual
// in a matrix, slice by FY / Site / Practitioner and drill to spot differences.
// When happy, drop the " New" suffix to switch the cards over.
//
// GRAIN NOTE: '_Metric Actuals' is FY x {global | one site | one practitioner}.
// So New matches the existing measure only when the context is a single FY and
// global / one site / one practitioner. Off-grain (a month, multi-select, or a
// site x practitioner intersection) New blanks or differs -- that is expected,
// not a data error.
//
// PREREQS:
//   1. Model must contain the '_Metric Actuals' table (add it after running
//      Meta.usp_Create_Gold_Views, then refresh).
//   2. Run TabularEditor_Shared.csx first (provides [_Target FY Key]).
//   3. Delete the "_New Actuals (compare)" display folder to remove the harness.
// -----------------------------------------------------------------------------

var t = Model.Tables["_Measures"];
var g = "_New Actuals (compare)";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// Production "new" actual: same grain logic as tDaily (sel_site / sel_prac) and
// same FY key as the targets ([_Target FY Key]); tenant pushed via TREATAS off
// the RLS-filtered List Practice Sites so '_Metric Actuals' needs no relationship.
Func<string,string> actNew = key => (@"VAR fy_key   = [_Target FY Key]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN
CALCULATE(
    MAX('_Metric Actuals'[Actual Value]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric]           = ""{key}"",
    '_Metric Actuals'[Period Value]     = fy_key,
    '_Metric Actuals'[fk Practice Site] = sel_site,
    '_Metric Actuals'[fk Practitioner]  = sel_prac
)").Replace("{key}", key);

// (existing measure name, "new" name, metric key, format)
var metrics = new[] {
    new [] {"Total Revenue",   "total_revenue",   "£#,##0"},
    new [] {"NHS Revenue",     "nhs_revenue",     "£#,##0"},
    new [] {"Private Revenue", "private_revenue", "£#,##0"},
    new [] {"New Patients",    "new_patients",    "#,##0"},
};

foreach (var m in metrics) {
    var existingName = m[0];
    var key          = m[1];
    var fmt          = m[2];
    add(existingName + " New",   actNew(key), fmt);
    add(existingName + " Delta", "[" + existingName + "] - [" + existingName + " New]", fmt);
}

Info("New actuals (compare) measures created in folder '" + g + "'.");
