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

// Production "new" SNAPSHOT STOCK: latest snapshot date in the selected period, then the
// stored Value at that date -- mirrors the live _KPI Snapshot snap_fk pattern. Respects
// site + practitioner. (key) -> metric.
Func<string,string> actNewSnap = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR snap_fk = CALCULATE( MAX('_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )
RETURN CALCULATE( SUM('_Metric Actuals'[Numerator]),
    '_Metric Actuals'[fk Date] = snap_fk,
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )").Replace("{key}", key);

// Same, but practitioner-agnostic (force prac = -1) -- mirrors REMOVEFILTERS('List Practitioners').
Func<string,string> actNewSnapNoP = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR snap_fk = CALCULATE( MAX('_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
RETURN CALCULATE( SUM('_Metric Actuals'[Numerator]),
    '_Metric Actuals'[fk Date] = snap_fk,
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )").Replace("{key}", key);

// Production "new" CURRENT-STATE value: ONE stored row per grain, read date-blind
// (REMOVEFILTERS the date dims) so it is period-independent -- mirrors the live cards that
// REMOVEFILTERS('List Date'). Grain via sel_site/sel_prac.
Func<string,string> actNewCurrent = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN CALCULATE( SUM('_Metric Actuals'[Numerator]),
    REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )").Replace("{key}", key);

// Current-state RATE: DIVIDE the one stored num/den row, also date-blind.
Func<string,string> actNewCurrentRate = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR n = CALCULATE( SUM('_Metric Actuals'[Numerator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )
VAR d = CALCULATE( SUM('_Metric Actuals'[Denominator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
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
    // Plan-grain rates (keyed on fk_Date_Created). Live cards are date-BLIND, so Delta is 0
    // only at the FULL date range; over a sub-period the daily version is the intended upgrade.
    new [] {"Treatment Acceptance Rate",      "acceptance_rate",                "#,##0.0%"},
    new [] {"Average Plan Value",             "avg_plan_value",                 "£#,##0"},
    // Daily-flow num/denom across two sources (rows keyed on each source's own date).
    new [] {"Revenue Per Clinical Hour",      "revenue_per_clinical_hour",      "£#,##0"},
    new [] {"Discounts",                      "discounts",                      "0.0%"},
};

foreach (var m in metrics) {
    add(m[0] + " New",   actNew(m[1]),     m[2]);
    add(m[0] + " Delta", "[" + m[0] + "] - [" + m[0] + " New]", m[2]);
}

foreach (var m in rates) {
    add(m[0] + " New",   actNewRate(m[1]), m[2]);
    add(m[0] + " Delta", "[" + m[0] + "] - [" + m[0] + " New]", m[2]);
}

// Snapshot stocks (latest snapshot in the selected period). Delta is ~0 at the full date
// range / no date slicer (where snap_fk = the overall latest weekly, what the live card shows).
// Practitioner-agnostic stocks (live card REMOVEFILTERS practitioners):
foreach (var m in new[] {
    new [] {"Active Patients",  "active_patients",  "#,##0"},
    new [] {"Lapsed Patients",  "lapsed_patients",  "#,##0"},
    new [] {"Overdue Recalls",  "overdue_recalls",  "#,##0"},
}) {
    add(m[0] + " New",   actNewSnapNoP(m[1]), m[2]);
    add(m[0] + " Delta", "[" + m[0] + "] - [" + m[0] + " New]", m[2]);
}
// Respects practitioner:
add("Outstanding Invoices New",   actNewSnap("outstanding_invoices"), "£#,##0");
add("Outstanding Invoices Delta", "[Outstanding Invoices] - [Outstanding Invoices New]", "£#,##0");

// Current-state values (date-blind). Delta is ~0 wherever the metric is stored at the card's
// grain; email/phone/retention are GLOBAL only this round (so they differ off-global).
foreach (var m in new[] {
    new [] {"Open Courses",                     "open_courses",               "#,##0"},
    new [] {"Open Courses Value",               "open_courses_value",         "£#,##0"},
    new [] {"Open Courses Without Appointment", "open_courses_without_appt",  "#,##0"},
    new [] {"Days Until Next 30 Minute Free",   "days_until_30min_free",      "#,##0"},
    new [] {"Days Until Next 1 Hour Free",      "days_until_1hr_free",        "#,##0"},
}) {
    add(m[0] + " New",   actNewCurrent(m[1]), m[2]);
    add(m[0] + " Delta", "[" + m[0] + "] - [" + m[0] + " New]", m[2]);
}
// Current-state rates (global only this round):
foreach (var m in new[] {
    new [] {"Email Details Rate",  "email_details_rate",  "#,##0.0%"},
    new [] {"Phone Details Rate",  "phone_details_rate",  "#,##0.0%"},
    new [] {"Retention Outlook",   "retention_outlook",   "#,##0.0%"},
}) {
    add(m[0] + " New",   actNewCurrentRate(m[1]), m[2]);
    add(m[0] + " Delta", "[" + m[0] + "] - [" + m[0] + " New]", m[2]);
}

Info("New actuals (compare) measures created in folder '" + g + "' (4 cumulative + 10 rates + 4 snapshot stocks + 8 current-state).");
