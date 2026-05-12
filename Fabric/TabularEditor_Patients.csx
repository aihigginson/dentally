var t = Model.Tables["_Measures"];
var g = "Patients KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Value measures ───────────────────────────────────────────────────────────

add("New Patients",
    @"CALCULATE(
    DISTINCTCOUNT('Aggregate Site Patient Practitioner Daily'[fk Patient]),
    'Aggregate Site Patient Practitioner Daily'[New Patient] = TRUE())",
    "#,##0");

add("Active Patients",
    @"COUNTROWS(
    FILTER('Aggregate Site Patient Current',
        'Aggregate Site Patient Current'[Active Patients] = TRUE()))",
    "#,##0");

add("Recall Effectiveness",
    @"DIVIDE(
    CALCULATE(COUNTROWS('_Recalls'), '_Recalls'[Status] = ""attended""),
    CALCULATE(COUNTROWS('_Recalls'), '_Recalls'[Due Date] <= TODAY()))",
    "#,##0.0%");

add("Patient Retention",
    @"DIVIDE(
    COUNTROWS(FILTER('Aggregate Site Patient Current',
        'Aggregate Site Patient Current'[Retained Patients] = TRUE())),
    COUNTROWS(FILTER('Aggregate Site Patient Current',
        'Aggregate Site Patient Current'[Active Patients] = TRUE())))",
    "#,##0.0%");

add("Recalls Overdue Not Sent",
    @"DIVIDE(
    COUNTROWS(FILTER('Aggregate Site Patient Current',
        'Aggregate Site Patient Current'[Recall Due]  = TRUE()
        && 'Aggregate Site Patient Current'[Recall Sent] = FALSE())),
    COUNTROWS(FILTER('Aggregate Site Patient Current',
        'Aggregate Site Patient Current'[Recall Due] = TRUE())))",
    "#,##0.0%");

// ── Target and variance measures ─────────────────────────────────────────────

add("New Patients Target",
    @"VAR period_key    = [_FY Period Key]
VAR annual        = MAXX(FILTER('_Targets',
    '_Targets'[Metric] = ""new_patients""
    && '_Targets'[Period Type] = ""annual""
    && '_Targets'[Period Value] = period_key), '_Targets'[Target Value])
VAR all_time_target = MAXX(FILTER('_Targets',
    '_Targets'[Metric] = ""new_patients""
    && '_Targets'[Period Type] = ""all_time""), '_Targets'[Target Value])
RETURN IF(ISBLANK(annual), all_time_target, annual) * [_Period Run Rate]",
    "#,##0");

add("New Patients vs Target",
    @"VAR actual = [New Patients]
VAR target = [New Patients Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Active Patients Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""active_patients""),
    '_Targets'[Target Value])",
    "#,##0");

add("Active Patients vs Target",
    @"VAR actual = [Active Patients]
VAR target = [Active Patients Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Recall Effectiveness Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""recall_compliance""),
    '_Targets'[Target Value])",
    "#,##0.0%");

add("Recall Effectiveness vs Target",
    @"VAR actual  = [Recall Effectiveness]
VAR target  = [Recall Effectiveness Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("Patient Retention Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""patient_retention""),
    '_Targets'[Target Value])",
    "#,##0.0%");

add("Patient Retention vs Target",
    @"VAR actual  = [Patient Retention]
VAR target  = [Patient Retention Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("Recalls Overdue Not Sent Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""recalls_overdue_not_sent""),
    '_Targets'[Target Value])",
    "#,##0.0%");

add("Recalls Overdue Not Sent vs Target",
    @"VAR actual  = [Recalls Overdue Not Sent]
VAR target  = [Recalls Overdue Not Sent Target]
VAR diff_pp = (target - actual) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

// ── BG colour measures ───────────────────────────────────────────────────────
// above + count  → relative %   (pct = (actual-target)/|target| * 100)
// above + percent → absolute pp (diff_pp = (actual-target) * 100)
// below + percent → absolute pp, sign inverted (lower is good)

add("New Patients BG",
    @"VAR actual   = [New Patients]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""new_patients""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""new_patients""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct >= band,   ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,  ""#f4a261"",
                       ""#c0392b"")",
    "");

add("Active Patients BG",
    @"VAR actual   = [Active Patients]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""active_patients""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""active_patients""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct >= band,   ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,  ""#f4a261"",
                       ""#c0392b"")",
    "");

add("Recall Effectiveness BG",
    @"VAR actual   = [Recall Effectiveness]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""recall_compliance""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""recall_compliance""), '_Targets'[Variance])
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp >= band,   ""#1a7f3c"",
    diff_pp >= 0,          ""#6abf7b"",
    diff_pp >= -band,  ""#f4a261"",
                           ""#c0392b"")",
    "");

add("Patient Retention BG",
    @"VAR actual   = [Patient Retention]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""patient_retention""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""patient_retention""), '_Targets'[Variance])
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp >= band,   ""#1a7f3c"",
    diff_pp >= 0,          ""#6abf7b"",
    diff_pp >= -band,  ""#f4a261"",
                           ""#c0392b"")",
    "");

add("Recalls Overdue Not Sent BG",
    @"VAR actual   = [Recalls Overdue Not Sent]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""recalls_overdue_not_sent""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""recalls_overdue_not_sent""), '_Targets'[Variance])
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp <= -band,  ""#1a7f3c"",
    diff_pp <= 0,          ""#6abf7b"",
    diff_pp <= band,   ""#f4a261"",
                           ""#c0392b"")",
    "");

Info("Patients KPI measures created.");
