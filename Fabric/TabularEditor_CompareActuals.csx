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

// Production "new" actual (DAILY-grain fact): SUM(Numerator) over the DATE CONTEXT,
// pushed via TREATAS('List Date'[pk Date] -> '_Metric Actuals'[fk Date]) -- exactly
// like tDaily. So ANY period works through the date filter (FY, YTD, Last 3M/12M/30d,
// or a free date-range slicer) with no special-casing. Grain via sel_site/sel_prac;
// tenant via TREATAS off the RLS-filtered List Practice Sites (no relationship needed).
Func<string,string> actNew = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN
CALCULATE(
    SUM('_Metric Actuals'[Numerator]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric]           = ""{key}"",
    '_Metric Actuals'[fk Practice Site] = sel_site,
    '_Metric Actuals'[fk Practitioner]  = sel_prac
)").Replace("{key}", key);

// Production "new" RATE: DIVIDE(SUM(Num), SUM(Den)) over the same date context --
// rates roll up by summing num + denom over the selected days (never average ratios).
Func<string,string> actNewRate = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR n = CALCULATE( SUM('_Metric Actuals'[Numerator]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )
VAR d = CALCULATE( SUM('_Metric Actuals'[Denominator]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )
RETURN DIVIDE(n, d)").Replace("{key}", key);

var metrics = new[] {
    new [] {"Total Revenue",   "total_revenue",   "£#,##0"},
    new [] {"NHS Revenue",     "nhs_revenue",     "£#,##0"},
    new [] {"Private Revenue", "private_revenue", "£#,##0"},
    new [] {"New Patients",    "new_patients",    "#,##0"},
};

// Tier-2 FY-period rates (num/denom in the fact)
var rates = new[] {
    new [] {"DNA Rate",                       "dna_rate",                       "#,##0.0%"},
    new [] {"Book Before You Leave",          "book_before_you_leave",          "#,##0.0%"},
    new [] {"Cancellation Frequency",         "cancellation_frequency",         "0.0%"},
    new [] {"Short Notice Cancellation Rate", "short_notice_cancellation_rate", "#,##0.0%"},
    new [] {"Exam Ratio",                     "exam_ratio",                     "#,##0.0%"},
    new [] {"Chair Utilisation",              "chair_utilisation",              "#,##0.0%"},
};

foreach (var m in metrics) {
    add(m[0] + " New",   actNew(m[1]),     m[2]);
    add(m[0] + " Delta", "[" + m[0] + "] - [" + m[0] + " New]", m[2]);
}

foreach (var m in rates) {
    add(m[0] + " New",   actNewRate(m[1]), m[2]);
    add(m[0] + " Delta", "[" + m[0] + "] - [" + m[0] + " New]", m[2]);
}

Info("New actuals (compare) measures created in folder '" + g + "' (4 cumulative + 6 rates).");
