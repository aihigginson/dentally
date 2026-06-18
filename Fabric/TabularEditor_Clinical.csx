// Clinical KPI measures — data-driven generation.
//
// Per-KPI Target / vs-Target / BG blocks are generated from per-KPI specs via the
// builder functions below. DAX is functionally identical to the previous
// hand-written version (DAX ignores whitespace). Value measures stay bespoke.
// All targets come from '_Effective Targets'.
//
// NOTE: Tabular Editor's C# has no string interpolation (dollar-prefixed strings),
// so templates are verbatim @"..." with {b}/{key} placeholders filled via .Replace().
//
// Builder variants used on this page:
//   Target : tEff (plain, count/currency) | tEff100 (ratios, /100)
//   vs     : vPct (relative %) | vPctP (+prefix) | vPctGrey (+No-data) | vPp (absolute pp)
//   BG     : bgHigherEff | bgHigherEffGrey | bgLowerEff | bgLowerEffGrey (relative-% bands)
//            bgHigherPp (pp band) | bgWithinPp (deviation-from-target band, closer is better)
// ("prefix" = the "⚠ " shown when a practitioner slicer is active on a
//  Supports_Practitioner = 0 metric.)

var t = Model.Tables["_Measures"];
var g = "Clinical KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Target builders ──────────────────────────────────────────────────────────
Func<string,string> tEff = key => (@"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""{key}"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site)").Replace("{key}", key);

Func<string,string> tEff100 = key => tEff(key) + " / 100";

// ── vs-Target builders ───────────────────────────────────────────────────────
Func<string,string> vPct = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPctP = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPctGrey = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(actual), ""No data"",
    IF(ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%"")))").Replace("{b}", b);

Func<string,string> vPp = b => (@"VAR actual  = [{b}]
VAR target  = [{b} Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))").Replace("{b}", b);

// ── BG builders (target+band inline from _Effective) ─────────────────────────
Func<string,string,string> bgHigherEff = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = CALCULATE(MAX('_Effective Targets'[Effective Target]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgHigherEffGrey = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = CALCULATE(MAX('_Effective Targets'[Effective Target]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual), ""#E0E0E0"",
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerEff = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = CALCULATE(MAX('_Effective Targets'[Effective Target]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerEffGrey = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = CALCULATE(MAX('_Effective Targets'[Effective Target]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual), ""#E0E0E0"",
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgHigherPp = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = CALCULATE(MAX('_Effective Targets'[Effective Target]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site) / 100
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

// "within": deviation from target — being close is good (Exam Ratio)
Func<string,string,string> bgWithinPp = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = CALCULATE(MAX('_Effective Targets'[Effective Target]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site) / 100
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site)
VAR dev      = ABS((actual - target) * 100)
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    dev <= band,     ""#1a7f3c"",
    dev <= band * 2, ""#6abf7b"",
    dev <= band * 3, ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Action<string,string,string,string,string> kpi = (baseName, fmt, targetDax, vsDax, bgDax) => {
    add(baseName + " Target",    targetDax, fmt);
    add(baseName + " vs Target", vsDax,     "");
    add(baseName + " BG",        bgDax,     "");
};

// ── Value measures (bespoke) ─────────────────────────────────────────────────

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

// Exam ratio: exam appointments / all appointments
add("Exam Ratio",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[Exam Count]),
    SUM('Aggregate Site Patient Practitioner Daily'[Appointments]))",
    "#,##0.0%");

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

// ── Derived Target / vs-Target / BG per KPI (data-driven) ─────────────────────
// acceptance_rate           → above + percent  → absolute pp
// open_courses              → below + count    → relative %  (lower is better)
// open_courses_without_appt → below + count    → relative %  (lower is better)
// exam_ratio                → within + percent → deviation from target (closer is better)
// open_courses_value        → above + currency → relative %
// avg_plan_value            → above + currency → relative %

kpi("Treatment Acceptance Rate",        "#,##0.0%", tEff100("acceptance_rate"),         vPp("Treatment Acceptance Rate"),                bgHigherPp("Treatment Acceptance Rate", "acceptance_rate"));
kpi("Open Courses",                     "#,##0",    tEff("open_courses"),               vPctGrey("Open Courses"),                        bgLowerEffGrey("Open Courses", "open_courses"));
kpi("Open Courses Without Appointment", "#,##0",    tEff("open_courses_without_appt"),  vPctP("Open Courses Without Appointment"),       bgLowerEff("Open Courses Without Appointment", "open_courses_without_appt"));
kpi("Exam Ratio",                       "#,##0.0%", tEff100("exam_ratio"),              vPp("Exam Ratio"),                               bgWithinPp("Exam Ratio", "exam_ratio"));
kpi("Open Courses Value",               "£#,##0",   tEff("open_courses_value"),         vPctGrey("Open Courses Value"),                  bgHigherEffGrey("Open Courses Value", "open_courses_value"));
kpi("Average Plan Value",               "£#,##0",   tEff("avg_plan_value"),             vPct("Average Plan Value"),                      bgHigherEff("Average Plan Value", "avg_plan_value"));

Info("Clinical KPI measures created (data-driven).");
