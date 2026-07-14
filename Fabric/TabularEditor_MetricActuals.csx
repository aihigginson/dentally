// TabularEditor_MetricActuals.csx
// -----------------------------------------------------------------------------
// Single script for the materialised metric-actuals layer (model table
// '_Metric Actuals', from Gold.Fact_Metric_Actuals). One place for the DAX
// builders + the metric->key map; pick what it does with MODE:
//
//   MODE = "apply"   -> PRODUCTION switch-over. Retargets each card measure's
//                       Expression IN PLACE onto '_Metric Actuals' (name, format,
//                       display folder, KPI wiring preserved) and removes the
//                       "_New Actuals (compare)" harness.
//   MODE = "compare" -> VALIDATION. Creates "<Metric> New" (reads the fact) and
//                       "<Metric> Delta" ([existing] - [New], 0 = ties out) in the
//                       "_New Actuals (compare)" folder. Leaves the real cards alone.
//
// GRAIN / BLANK: measures resolve at the selected site x practitioner grain; where
// the fact has no row at that grain they return BLANK (not the undrilled total) --
// e.g. site for plan/aggregate metrics, practitioner for the patient stocks.
//
// PREREQ: the model must contain '_Metric Actuals' (PBI view from
// Meta.usp_Create_Gold_Views), refreshed. For MODE="apply", run after the per-page
// measure scripts (which create the measures this retargets) + TabularEditor_Shared.
// -----------------------------------------------------------------------------

string MODE = "apply";   // "apply" | "compare"

var t = Model.Tables["_Measures"];
var g = "_New Actuals (compare)";

// Always clear any existing compare harness first (apply removes it; compare rebuilds it).
foreach (var m in t.Measures.Where(m => m.DisplayFolder == g).ToList()) m.Delete();

// --- DAX builders (5 shapes) ------------------------------------------------------
// Cumulative: sum over the date context.
Func<string,string> dCum = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
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

// Rate over the date context: DIVIDE(sum num, sum den).
Func<string,string> dRate = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
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

// Snapshot stock: latest snapshot date in the selected period, then the value at it.
Func<string,string> dSnap = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR snap_fk = CALCULATE( MAX('_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )
RETURN CALCULATE( SUM('_Metric Actuals'[Numerator]),
    '_Metric Actuals'[fk Date] = snap_fk,
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )").Replace("{key}", key);

// Current-state value: ONE row per grain, read date-blind (period-independent).
Func<string,string> dCur = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN CALCULATE( SUM('_Metric Actuals'[Numerator]),
    REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )").Replace("{key}", key);

// Current-state rate: date-blind DIVIDE.
Func<string,string> dCurRate = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR n = CALCULATE( SUM('_Metric Actuals'[Numerator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )
VAR d = CALCULATE( SUM('_Metric Actuals'[Denominator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )
RETURN DIVIDE(n, d)").Replace("{key}", key);

Func<string,string,string> build = (shape, key) => {
    if (shape == "cum")     return dCum(key);
    if (shape == "rate")    return dRate(key);
    if (shape == "snap")    return dSnap(key);
    if (shape == "cur")     return dCur(key);
    if (shape == "currate") return dCurRate(key);
    return "";
};

// --- metric -> { display name, fact key, shape, format } --------------------------
var metrics = new[] {
    new[]{"Total Revenue",                    "total_revenue",                  "cum",     "£#,##0"},
    new[]{"NHS Revenue",                      "nhs_revenue",                    "cum",     "£#,##0"},
    new[]{"Private Revenue",                  "private_revenue",                "cum",     "£#,##0"},
    new[]{"New Patients",                     "new_patients",                   "cum",     "#,##0"},
    new[]{"DNA Rate",                         "dna_rate",                       "rate",    "#,##0.0%"},
    new[]{"Book Before You Leave",            "book_before_you_leave",          "rate",    "#,##0.0%"},
    new[]{"Cancellation Frequency",           "cancellation_frequency",         "rate",    "0.0%"},
    new[]{"Short Notice Cancellation Rate",   "short_notice_cancellation_rate", "rate",    "#,##0.0%"},
    new[]{"Exam Ratio",                       "exam_ratio",                     "rate",    "#,##0.0%"},
    new[]{"Diary Fill",                       "diary_fill",                     "rate",    "#,##0.0%"},
    new[]{"Chair Utilisation",                "chair_utilisation",              "rate",    "#,##0.0%"},
    new[]{"Patient Tracked in Surgery",       "patient_tracked_in_surgery",     "rate",    "#,##0.0%"},
    new[]{"Average Plan Value",               "avg_plan_value",                 "rate",    "£#,##0"},
    new[]{"Revenue Per Clinical Hour",        "revenue_per_clinical_hour",      "rate",    "£#,##0"},
    new[]{"Discounts",                        "discounts",                      "rate",    "0.0%"},
    new[]{"Deposit Value",                    "deposit_ratio",                  "rate",    "0.0%"},
    new[]{"Active Patients",                  "active_patients",                "snap",    "#,##0"},
    new[]{"Lapsed Patients",                  "lapsed_patients",                "cum",     "#,##0"},
    new[]{"Lapsed (Set Inactive)",            "lapsed_deactivated",             "cum",     "#,##0"},
    new[]{"Lapsed (Silently)",                "lapsed_calculated",              "cum",     "#,##0"},
    new[]{"Outstanding Invoices",             "outstanding_invoices",           "snap",    "£#,##0"},
    new[]{"Overdue Recalls",                  "overdue_recalls",                "cur",     "#,##0"},
    // Open Courses family now reads Gold.Fact_Treatment_Plans LIVE (via '_Treatment Plans' +
    // [Course Status]) in TabularEditor_Clinical.csx -- NOT materialised here -- so the item-level
    // rules + 3-month recency band evaluate at query time (no row rebuild as courses age).
    new[]{"Days Until Next 30 Minute Free",   "days_until_30min_free",          "cur",     "#,##0"},
    new[]{"Email Details Rate",               "email_details_rate",             "currate", "#,##0.0%"},
    new[]{"Phone Details Rate",               "phone_details_rate",             "currate", "#,##0.0%"},
    new[]{"Dentist Retention Outlook",        "dentist_retention_outlook",      "currate", "#,##0.0%"},
    new[]{"Hygiene Retention Outlook",        "hygiene_retention_outlook",      "currate", "#,##0.0%"},
    new[]{"Dentist Recall Conversion",        "dentist_recall_conversion",      "currate", "#,##0.0%"},
    new[]{"Hygiene Recall Conversion",        "hygiene_recall_conversion",      "currate", "#,##0.0%"},
};

int applied = 0, missing = 0, made = 0;
foreach (var m in metrics) {
    string name = m[0], key = m[1], shape = m[2], fmt = m[3];
    string dax = build(shape, key);
    if (MODE == "apply") {
        var meas = t.Measures.FirstOrDefault(x => x.Name == name);
        if (meas == null) { Warning("measure not found, skipped: " + name); missing++; continue; }
        meas.Expression = dax; applied++;
    } else {
        var nu = t.AddMeasure(name + " New",   dax);                                 nu.DisplayFolder = g; nu.FormatString = fmt;
        var de = t.AddMeasure(name + " Delta", "[" + name + "] - [" + name + " New]"); de.DisplayFolder = g; de.FormatString = fmt;
        made += 2;
    }
}

if (MODE == "apply")
    Info("APPLY: " + applied + " card measures retargeted onto '_Metric Actuals', " + missing + " not found; compare harness removed.");
else
    Info("COMPARE: " + made + " measures created in '" + g + "'. Set MODE=\"apply\" to switch the cards over.");
