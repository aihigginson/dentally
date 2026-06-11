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

// Acceptance rate: plans that have progressed to having a start date / all plans.
// Routes through _Treatment Plan Items[fk Treatment Plan] to pick up the practitioner slicer,
// because List Treatment Plans has no fk_Practitioner surrogate key relationship.
add("Treatment Acceptance Rate",
    @"VAR practitioner_plans = DISTINCT('_Treatment Plan Items'[fk Treatment Plan])
RETURN DIVIDE(
    CALCULATE(
        SUM('List Treatment Plans'[Treatment Plan Count]),
        'List Treatment Plans'[Start Date] <> BLANK(),
        TREATAS(practitioner_plans, 'List Treatment Plans'[pk Treatment Plan])
    ),
    CALCULATE(
        SUM('List Treatment Plans'[Treatment Plan Count]),
        TREATAS(practitioner_plans, 'List Treatment Plans'[pk Treatment Plan])
    )
)",
    "#,##0.0%");

// Open courses: live count of incomplete, started plans from List Treatment Plans.
// Routes through _Treatment Plan Items[fk Treatment Plan] to pick up the practitioner slicer.
add("Open Courses",
    @"VAR practitioner_plans = DISTINCT('_Treatment Plan Items'[fk Treatment Plan])
RETURN CALCULATE(
    SUM('List Treatment Plans'[Treatment Plan Count]),
    'List Treatment Plans'[Completed]         = FALSE(),
    NOT ISBLANK('List Treatment Plans'[Start Date]),
    TREATAS(practitioner_plans, 'List Treatment Plans'[pk Treatment Plan])
)",
    "#,##0");

// Open courses with no future appointment booked.
// Routes through _Treatment Plan Items to pick up the practitioner slicer,
// then checks List Patients[Next Appointment Date] (current-state) for no future booking.
add("Open Courses Without Appointment",
    @"VAR today = TODAY()
VAR open_plan_patients =
    CALCULATETABLE(
        DISTINCT('_Treatment Plan Items'[fk Patient]),
        '_Treatment Plan Items'[Completed]        = FALSE(),
        '_Treatment Plan Items'[Charged]          = FALSE(),
        'List Treatment Plans'[Completed]         = FALSE(),
        NOT ISBLANK('List Treatment Plans'[Start Date])
    )
RETURN
CALCULATE(
    COUNTROWS('List Patients'),
    TREATAS(open_plan_patients, 'List Patients'[pk Patient]),
    'List Patients'[pk Patient] > 0,
    FILTER(
        'List Patients',
        ISBLANK('List Patients'[Next Appointment Date])
            || 'List Patients'[Next Appointment Date] <= today
    )
)",
    "#,##0");

// Treatment items completed in the selected period, summed by price.
// Activates the inactive fk Date Completed → Dim Date relationship so the
// date slicer filters by completion date rather than creation date.
add("Treatment Completed Price",
    @"CALCULATE(
    SUM('_Treatment Plan Items'[Price]),
    '_Treatment Plan Items'[Completed] = TRUE(),
    USERELATIONSHIP('_Treatment Plan Items'[fk Date Completed], 'Dim Date'[pk Date])
)",
    "£#,##0.00");

// Exam ratio: exam appointments / all appointments
add("Exam Ratio",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[Exam Count]),
    SUM('Aggregate Site Patient Practitioner Daily'[Appointments]))",
    "#,##0.0%");

// ── Target and variance measures ─────────────────────────────────────────────
// All use _Effective Targets (period-resolved, site hierarchy pre-computed).

add("Treatment Acceptance Rate Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""acceptance_rate"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site) / 100",
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
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""open_courses"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site)",
    "#,##0");

add("Open Courses vs Target",
    @"VAR actual = [Open Courses]
VAR target = [Open Courses Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(actual), ""No data"",
    IF(ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%"")))",
    "");

add("Open Courses Without Appointment Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""open_courses_without_appt"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site)",
    "#,##0");

add("Open Courses Without Appointment vs Target",
    @"VAR actual = [Open Courses Without Appointment]
VAR target = [Open Courses Without Appointment Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Exam Ratio Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""exam_ratio"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site) / 100",
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
    @"VAR actual    = [Treatment Acceptance Rate]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
VAR target     = CALCULATE(MAX('_Effective Targets'[Effective Target]),  TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""acceptance_rate"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site) / 100
VAR band       = CALCULATE(MAX('_Effective Targets'[Effective Variance]),TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""acceptance_rate"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR diff_pp    = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Open Courses BG",
    @"VAR actual    = [Open Courses]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
VAR target     = CALCULATE(MAX('_Effective Targets'[Effective Target]),  TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""open_courses"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR band       = CALCULATE(MAX('_Effective Targets'[Effective Variance]),TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""open_courses"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR pct        = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual),  ""#E0E0E0"",
    ISBLANK(target),  ""#FFFFFF"",
    pct <= -band,     ""#1a7f3c"",
    pct <= 0,         ""#6abf7b"",
    pct <= band,      ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Open Courses Without Appointment BG",
    @"VAR actual    = [Open Courses Without Appointment]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
VAR target     = CALCULATE(MAX('_Effective Targets'[Effective Target]),  TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""open_courses_without_appt"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR band       = CALCULATE(MAX('_Effective Targets'[Effective Variance]),TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""open_courses_without_appt"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR pct        = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct <= -band,     ""#1a7f3c"",
    pct <= 0,         ""#6abf7b"",
    pct <= band,      ""#f4a261"",
                      ""#c0392b"")",
    "");

// within: deviation from target — being close is good
add("Exam Ratio BG",
    @"VAR actual    = [Exam Ratio]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
VAR target     = CALCULATE(MAX('_Effective Targets'[Effective Target]),  TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""exam_ratio"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site) / 100
VAR band       = CALCULATE(MAX('_Effective Targets'[Effective Variance]),TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""exam_ratio"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR dev        = ABS((actual - target) * 100)
RETURN SWITCH(TRUE(),
    ISBLANK(target),    ""#FFFFFF"",
    dev <= band,        ""#1a7f3c"",
    dev <= band * 2,    ""#6abf7b"",
    dev <= band * 3,    ""#f4a261"",
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

// Average private treatment value per plan that has been started.
// Routes through _Treatment Plan Items[fk Treatment Plan] to pick up the practitioner slicer.
add("Average Plan Value",
    @"VAR practitioner_plans = DISTINCT('_Treatment Plan Items'[fk Treatment Plan])
RETURN DIVIDE(
    CALCULATE(
        SUM('List Treatment Plans'[Private Treatment Value]),
        TREATAS(practitioner_plans, 'List Treatment Plans'[pk Treatment Plan])
    ),
    CALCULATE(
        COUNTROWS('List Treatment Plans'),
        NOT ISBLANK('List Treatment Plans'[Start Date]),
        TREATAS(practitioner_plans, 'List Treatment Plans'[pk Treatment Plan])
    )
)",
    "£#,##0");

add("Open Courses Value Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""open_courses_value"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site)",
    "£#,##0");

add("Open Courses Value vs Target",
    @"VAR actual = [Open Courses Value]
VAR target = [Open Courses Value Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(actual), ""No data"",
    IF(ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%"")))",
    "");

add("Average Plan Value Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""avg_plan_value"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site)",
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
    @"VAR actual    = [Open Courses Value]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
VAR target     = CALCULATE(MAX('_Effective Targets'[Effective Target]),  TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""open_courses_value"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR band       = CALCULATE(MAX('_Effective Targets'[Effective Variance]),TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""open_courses_value"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR pct        = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual),  ""#E0E0E0"",
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Average Plan Value BG",
    @"VAR actual    = [Average Plan Value]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
VAR target     = CALCULATE(MAX('_Effective Targets'[Effective Target]),  TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""avg_plan_value"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR band       = CALCULATE(MAX('_Effective Targets'[Effective Variance]),TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),'_Effective Targets'[Metric] = ""avg_plan_value"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR pct        = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

Info("Clinical KPI measures created.");
