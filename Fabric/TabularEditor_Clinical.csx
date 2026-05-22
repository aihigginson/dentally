var t = Model.Tables["_Measures"];
var g = "Clinical KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Value measures ───────────────────────────────────────────────────────────

// Acceptance rate: plans that have progressed to having a start date / all plans
add("Treatment Acceptance Rate",
    @"DIVIDE(
    CALCULATE(SUM('List Treatment Plans'[Treatment Plan Count]),
        'List Treatment Plans'[Start Date] <> BLANK()),
    SUM('List Treatment Plans'[Treatment Plan Count]))",
    "#,##0.0%");

// Open courses: plans not yet completed
add("Open Courses",
    @"SUMX(
    FILTER('List Treatment Plans',
        'List Treatment Plans'[Completed] = FALSE()),
    'List Treatment Plans'[Treatment Plan Count])",
    "#,##0");

// Open courses with no future appointment booked
add("Open Courses Without Appointment",
    @"CALCULATE(
    DISTINCTCOUNT('Aggregate Site Patient Practitioner Daily'[fk Patient]),
    'Aggregate Site Patient Practitioner Daily'[Open Treatment Plan] > 0,
    'Aggregate Site Patient Practitioner Daily'[Future Appointment] = FALSE())",
    "#,##0");

// Exam ratio: exam appointments / all appointments
add("Exam Ratio",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[Exam Count]),
    SUM('Aggregate Site Patient Practitioner Daily'[Appointments]))",
    "#,##0.0%");

// ── Target and variance measures ─────────────────────────────────────────────

add("Treatment Acceptance Rate Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""acceptance_rate""),
    '_Targets'[Target Value])",
    "#,##0.0%");

add("Treatment Acceptance Rate vs Target",
    @"VAR actual  = [Treatment Acceptance Rate]
VAR target  = [Treatment Acceptance Rate Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("Open Courses Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""open_courses""),
    '_Targets'[Target Value])",
    "#,##0");

add("Open Courses vs Target",
    @"VAR actual = [Open Courses]
VAR target = [Open Courses Target]
VAR pct    = DIVIDE(target - actual, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Open Courses Without Appointment Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""open_courses_without_appt""),
    '_Targets'[Target Value])",
    "#,##0");

add("Open Courses Without Appointment vs Target",
    @"VAR actual = [Open Courses Without Appointment]
VAR target = [Open Courses Without Appointment Target]
VAR pct    = DIVIDE(target - actual, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Exam Ratio Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""exam_ratio""),
    '_Targets'[Target Value])",
    "#,##0.0%");

add("Exam Ratio vs Target",
    @"VAR actual  = [Exam Ratio]
VAR target  = [Exam Ratio Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

// ── BG colour measures ───────────────────────────────────────────────────────
// acceptance_rate  → above + percent → absolute pp
// open_courses     → below + count   → relative %  (lower is better)
// open_courses_without_appt → below + count → relative %
// exam_ratio       → within + percent → absolute pp deviation from target

add("Treatment Acceptance Rate BG",
    @"VAR actual   = [Treatment Acceptance Rate]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""acceptance_rate""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""acceptance_rate""), '_Targets'[Variance])
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp >= band,   ""#1a7f3c"",
    diff_pp >= 0,          ""#6abf7b"",
    diff_pp >= -band,  ""#f4a261"",
                           ""#c0392b"")",
    "");

add("Open Courses BG",
    @"VAR actual   = [Open Courses]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""open_courses""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""open_courses""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct <= -band,  ""#1a7f3c"",
    pct <= 0,          ""#6abf7b"",
    pct <= band,   ""#f4a261"",
                       ""#c0392b"")",
    "");

add("Open Courses Without Appointment BG",
    @"VAR actual   = [Open Courses Without Appointment]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""open_courses_without_appt""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""open_courses_without_appt""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct <= -band,  ""#1a7f3c"",
    pct <= 0,          ""#6abf7b"",
    pct <= band,   ""#f4a261"",
                       ""#c0392b"")",
    "");

// within: deviation from target — being close is good
add("Exam Ratio BG",
    @"VAR actual   = [Exam Ratio]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""exam_ratio""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""exam_ratio""), '_Targets'[Variance])
VAR dev      = ABS((actual - target) * 100)
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    dev <= band,       ""#1a7f3c"",
    dev <= band * 2,   ""#6abf7b"",
    dev <= band * 3,   ""#f4a261"",
                           ""#c0392b"")",
    "");

// ── Home page measures ────────────────────────────────────────────────────────

// Open Courses Value: semi-additive point-in-time — picks the latest weekly snapshot
// in the slicer selection so the card always shows one value, not a sum over time.
add("Open Courses Value",
    @"VAR last_date =
    MAXX(
        FILTER( ALLSELECTED( '_KPI Snapshot' ), '_KPI Snapshot'[Snapshot Grain] = ""weekly"" ),
        '_KPI Snapshot'[fk Date]
    )
RETURN
CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[fk Date]        = last_date,
    '_KPI Snapshot'[Metric]         = ""open_courses_value"",
    '_KPI Snapshot'[Snapshot Grain] = ""weekly""
)",
    "£#,##0");

// Average private treatment value per plan that has been started
add("Average Plan Value",
    @"DIVIDE(
    SUM('List Treatment Plans'[Private Treatment Value]),
    CALCULATE(
        COUNTROWS('List Treatment Plans'),
        NOT ISBLANK('List Treatment Plans'[Start Date])))",
    "£#,##0");

add("Open Courses Value Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""open_courses_value""),
    '_Targets'[Target Value])",
    "£#,##0");

add("Open Courses Value vs Target",
    @"VAR actual = [Open Courses Value]
VAR target = [Open Courses Value Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Average Plan Value Target",
    @"MAXX(FILTER('_Targets', '_Targets'[Metric] = ""avg_plan_value""),
    '_Targets'[Target Value])",
    "£#,##0");

add("Average Plan Value vs Target",
    @"VAR actual = [Average Plan Value]
VAR target = [Average Plan Value Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Open Courses Value BG",
    @"VAR actual = [Open Courses Value]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""open_courses_value""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""open_courses_value""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Average Plan Value BG",
    @"VAR actual = [Average Plan Value]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""avg_plan_value""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""avg_plan_value""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

Info("Clinical KPI measures created.");
