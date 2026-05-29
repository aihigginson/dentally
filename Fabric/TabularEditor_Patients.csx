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

// Lapsed: point-in-time stock count from KPI Snapshot (A3).
// Value = patients whose 24-month exam clock has expired as of the snapshot date.
add("Lapsed Patients",
    @"VAR snap_fk =
    CALCULATE(
        MAXX(
            FILTER( ALLSELECTED( '_KPI Snapshot' ), '_KPI Snapshot'[Snapshot Grain] = ""weekly"" ),
            '_KPI Snapshot'[fk Date]
        ),
        REMOVEFILTERS( 'List Practitioners' )
    )
RETURN
CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[fk Date]        = snap_fk,
    '_KPI Snapshot'[Metric]         = ""lapsed_patients"",
    '_KPI Snapshot'[Snapshot Grain] = ""weekly"",
    REMOVEFILTERS( 'List Practitioners' )
)",
    "#,##0");

// Net Patient Growth uses an inline lapsed-in-period calculation so it remains
// a flow metric (new arrivals minus exits in the period) independent of the
// point-in-time Lapsed Patients snapshot measure above.
add("Net Patient Growth",
    @"VAR period_start = MIN('List Date'[Full Date])
VAR period_end   = MAX('List Date'[Full Date])
VAR lapsed_flow  =
    COUNTROWS(
        FILTER(
            ALL('List Patients'),
            NOT ISBLANK('List Patients'[Last Exam Date])
            && EDATE('List Patients'[Last Exam Date], 24) >= period_start
            && EDATE('List Patients'[Last Exam Date], 24) <= period_end
            && NOT ISBLANK('List Patients'[First Appointment Date])
            && 'List Patients'[First Appointment Date] < period_start
        )
    )
RETURN [New Patients] - lapsed_flow",
    "#,##0");

// Retention Outlook: % of in-scope recall patients who have a booking.
// Is_In_Scope and Is_Booked are pre-computed in Gold.usp_Load_Fact_Recalls,
// replacing the previous FILTER/SELECTCOLUMNS/UNION/INTERSECT set operations.
// REMOVEFILTERS('List Date') keeps the metric independent of the date slicer;
// tenant RLS still propagates through the _Recalls relationship.
add("Retention Outlook",
    @"VAR due =
    CALCULATE(
        DISTINCTCOUNT( '_Recalls'[fk Patient] ),
        '_Recalls'[Is In Scope] = TRUE(),
        REMOVEFILTERS( 'List Date' )
    )
VAR booked =
    CALCULATE(
        DISTINCTCOUNT( '_Recalls'[fk Patient] ),
        '_Recalls'[Is In Scope] = TRUE(),
        '_Recalls'[Is Booked]   = TRUE(),
        REMOVEFILTERS( 'List Date' )
    )
RETURN DIVIDE( booked, due )",
    "#,##0.0%");

// Active Patients: point-in-time count from KPI Snapshot (A3).
add("Active Patients",
    @"VAR snap_fk =
    CALCULATE(
        MAXX(
            FILTER( ALLSELECTED( '_KPI Snapshot' ), '_KPI Snapshot'[Snapshot Grain] = ""weekly"" ),
            '_KPI Snapshot'[fk Date]
        ),
        REMOVEFILTERS( 'List Practitioners' )
    )
RETURN
CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[fk Date]        = snap_fk,
    '_KPI Snapshot'[Metric]         = ""active_patients"",
    '_KPI Snapshot'[Snapshot Grain] = ""weekly"",
    REMOVEFILTERS( 'List Practitioners' )
)",
    "#,##0");

// Recall Effectiveness: % of in-scope open recalls where at least one reminder
// has been sent. Dentally deletes attended recalls so Status = "attended" never
// exists — this replaces the previous broken measure.
add("Recall Effectiveness",
    @"VAR in_scope =
    CALCULATE(
        COUNTROWS( '_Recalls' ),
        '_Recalls'[Is In Scope] = TRUE(),
        REMOVEFILTERS( 'List Date' )
    )
VAR contacted =
    CALCULATE(
        COUNTROWS( '_Recalls' ),
        '_Recalls'[Is In Scope]      = TRUE(),
        '_Recalls'[Is Reminder Sent] = TRUE(),
        REMOVEFILTERS( 'List Date' )
    )
RETURN DIVIDE( contacted, in_scope )",
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
    @"VAR period_key = [_FY Period Key]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR annual     = COALESCE(
    MAXX(FILTER('_Targets',
        '_Targets'[Tenant ID] = sel_tenant
        && '_Targets'[Metric] = ""new_patients""
        && '_Targets'[Period Type] = ""annual""
        && '_Targets'[Period Value] = period_key
        && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets',
        '_Targets'[Tenant ID] = sel_tenant
        && '_Targets'[Metric] = ""new_patients""
        && '_Targets'[Period Type] = ""annual""
        && '_Targets'[Period Value] = period_key
        && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR all_time_target = COALESCE(
    MAXX(FILTER('_Targets',
        '_Targets'[Tenant ID] = sel_tenant
        && '_Targets'[Metric] = ""new_patients""
        && '_Targets'[Period Type] = ""all_time""
        && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets',
        '_Targets'[Tenant ID] = sel_tenant
        && '_Targets'[Metric] = ""new_patients""
        && '_Targets'[Period Type] = ""all_time""
        && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
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

add("Net Patient Growth Target",
    @"VAR period_key = [_FY Period Key]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR annual     = COALESCE(
    MAXX(FILTER('_Targets',
        '_Targets'[Tenant ID] = sel_tenant
        && '_Targets'[Metric] = ""net_patient_growth""
        && '_Targets'[Period Type] = ""annual""
        && '_Targets'[Period Value] = period_key
        && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets',
        '_Targets'[Tenant ID] = sel_tenant
        && '_Targets'[Metric] = ""net_patient_growth""
        && '_Targets'[Period Type] = ""annual""
        && '_Targets'[Period Value] = period_key
        && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR all_time_target = COALESCE(
    MAXX(FILTER('_Targets',
        '_Targets'[Tenant ID] = sel_tenant
        && '_Targets'[Metric] = ""net_patient_growth""
        && '_Targets'[Period Type] = ""all_time""
        && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets',
        '_Targets'[Tenant ID] = sel_tenant
        && '_Targets'[Metric] = ""net_patient_growth""
        && '_Targets'[Period Type] = ""all_time""
        && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
RETURN IF(ISBLANK(annual), all_time_target, annual) * [_Period Run Rate]",
    "#,##0");

add("Net Patient Growth vs Target",
    @"VAR actual = [Net Patient Growth]
VAR target = [Net Patient Growth Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Lapsed Patients Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""lapsed_patients"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""lapsed_patients"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))",
    "#,##0");

add("Lapsed Patients vs Target",
    @"VAR actual = [Lapsed Patients]
VAR target = [Lapsed Patients Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(actual), ""No data"",
    IF(ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%"")))",
    "");

add("Active Patients Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""active_patients"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""active_patients"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))",
    "#,##0");

add("Active Patients vs Target",
    @"VAR actual = [Active Patients]
VAR target = [Active Patients Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(actual), ""No data"",
    IF(ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%"")))",
    "");

add("Recall Effectiveness Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recall_compliance"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recall_compliance"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100",
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
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""patient_retention"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""patient_retention"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100",
    "#,##0.0%");

add("Patient Retention vs Target",
    @"VAR actual  = [Patient Retention]
VAR target  = [Patient Retention Target]
VAR diff_pp = (actual - target) * 100
VAR prefix  = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("Recalls Overdue Not Sent Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recalls_overdue_not_sent"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recalls_overdue_not_sent"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100",
    "#,##0.0%");

add("Recalls Overdue Not Sent vs Target",
    @"VAR actual  = [Recalls Overdue Not Sent]
VAR target  = [Recalls Overdue Not Sent Target]
VAR diff_pp = (actual - target) * 100
VAR prefix  = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

// ── BG colour measures ───────────────────────────────────────────────────────
// above + count  → relative %   (pct = (actual-target)/|target| * 100)
// above + percent → absolute pp (diff_pp = (actual-target) * 100)
// below + percent → absolute pp, sign inverted (lower is good)

add("New Patients BG",
    @"VAR actual   = [New Patients]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""new_patients"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""new_patients"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""new_patients"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""new_patients"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct >= band,   ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,  ""#f4a261"",
                       ""#c0392b"")",
    "");

add("Net Patient Growth BG",
    @"VAR actual   = [Net Patient Growth]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""net_patient_growth"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""net_patient_growth"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""net_patient_growth"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""net_patient_growth"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Lapsed Patients BG",
    @"VAR actual   = [Lapsed Patients]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""lapsed_patients"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""lapsed_patients"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""lapsed_patients"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""lapsed_patients"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual), ""#E0E0E0"",
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Active Patients BG",
    @"VAR actual   = [Active Patients]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""active_patients"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""active_patients"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""active_patients"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""active_patients"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual),   ""#E0E0E0"",
    ISBLANK(target),   ""#FFFFFF"",
    pct >= band,       ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,      ""#f4a261"",
                       ""#c0392b"")",
    "");

add("Recall Effectiveness BG",
    @"VAR actual   = [Recall Effectiveness]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recall_compliance"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recall_compliance"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recall_compliance"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recall_compliance"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
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
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""patient_retention"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""patient_retention"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""patient_retention"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""patient_retention"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
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
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recalls_overdue_not_sent"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recalls_overdue_not_sent"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recalls_overdue_not_sent"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""recalls_overdue_not_sent"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp <= -band,  ""#1a7f3c"",
    diff_pp <= 0,          ""#6abf7b"",
    diff_pp <= band,   ""#f4a261"",
                           ""#c0392b"")",
    "");

add("Retention Outlook Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""retention_outlook"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""retention_outlook"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100",
    "#,##0.0%");

// Above is good, percentage metric — variance expressed as absolute pp
add("Retention Outlook vs Target",
    @"VAR actual  = [Retention Outlook]
VAR target  = [Retention Outlook Target]
VAR diff_pp = ( actual - target ) * 100
VAR prefix  = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK( actual ), ""No data"",
    IF( ISBLANK( target ), BLANK(),
    prefix & IF( diff_pp >= 0,
        ""▲ "" & FORMAT( diff_pp,      ""0.0"" ) & ""pp"",
        ""▼ "" & FORMAT( ABS(diff_pp), ""0.0"" ) & ""pp"" )))",
    "");

add("Retention Outlook BG",
    @"VAR actual   = [Retention Outlook]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""retention_outlook"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""retention_outlook"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""retention_outlook"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""retention_outlook"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR diff_pp  = ( actual - target ) * 100
RETURN SWITCH( TRUE(),
    ISBLANK( actual ), ""#E0E0E0"",
    ISBLANK( target ), ""#FFFFFF"",
    diff_pp >= band,   ""#1a7f3c"",
    diff_pp >= 0,      ""#6abf7b"",
    diff_pp >= -band,  ""#f4a261"",
                       ""#c0392b"" )",
    "");

// ── Home Detail measures ──────────────────────────────────────────────────────

// Overdue Recalls: point-in-time count from KPI Snapshot (A3).
add("Overdue Recalls",
    @"VAR snap_fk =
    CALCULATE(
        MAXX(
            FILTER( ALLSELECTED( '_KPI Snapshot' ), '_KPI Snapshot'[Snapshot Grain] = ""weekly"" ),
            '_KPI Snapshot'[fk Date]
        ),
        REMOVEFILTERS( 'List Practitioners' )
    )
RETURN
CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[fk Date]        = snap_fk,
    '_KPI Snapshot'[Metric]         = ""overdue_recalls"",
    '_KPI Snapshot'[Snapshot Grain] = ""weekly"",
    REMOVEFILTERS( 'List Practitioners' )
)",
    "#,##0");

// Email Details Rate: % of patients with a non-blank email address
add("Email Details Rate",
    @"DIVIDE(
    CALCULATE(
        SUM('List Patients'[Patient Count]),
        NOT ISBLANK('List Patients'[Email Address])),
    SUM('List Patients'[Patient Count]))",
    "#,##0.0%");

// Phone Details Rate: % of patients with at least one phone number (mobile or home)
add("Phone Details Rate",
    @"DIVIDE(
    CALCULATE(
        SUM('List Patients'[Patient Count]),
        NOT ISBLANK('List Patients'[Mobile Phone])
        || NOT ISBLANK('List Patients'[Home Phone])),
    SUM('List Patients'[Patient Count]))",
    "#,##0.0%");

add("Overdue Recalls Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""overdue_recalls"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""overdue_recalls"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))",
    "#,##0");

add("Overdue Recalls vs Target",
    @"VAR actual = [Overdue Recalls]
VAR target = [Overdue Recalls Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(actual), ""No data"",
    IF(ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%"")))",
    "");

add("Email Details Rate Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""email_details_rate"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""email_details_rate"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100",
    "#,##0.0%");

add("Email Details Rate vs Target",
    @"VAR actual  = [Email Details Rate]
VAR target  = [Email Details Rate Target]
VAR diff_pp = (actual - target) * 100
VAR prefix  = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("Phone Details Rate Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""phone_details_rate"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""phone_details_rate"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100",
    "#,##0.0%");

add("Phone Details Rate vs Target",
    @"VAR actual  = [Phone Details Rate]
VAR target  = [Phone Details Rate Target]
VAR diff_pp = (actual - target) * 100
VAR prefix  = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("Overdue Recalls BG",
    @"VAR actual   = [Overdue Recalls]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""overdue_recalls"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""overdue_recalls"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""overdue_recalls"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""overdue_recalls"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual), ""#E0E0E0"",
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Email Details Rate BG",
    @"VAR actual   = [Email Details Rate]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""email_details_rate"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""email_details_rate"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""email_details_rate"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""email_details_rate"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Phone Details Rate BG",
    @"VAR actual   = [Phone Details Rate]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""phone_details_rate"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""phone_details_rate"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""phone_details_rate"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""phone_details_rate"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")",
    "");

Info("Patients KPI measures created.");
