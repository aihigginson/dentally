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
    '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)").Replace("{key}", key);

Func<string,string> tEff100 = key => tEff(key) + " / 100";

// tEffAdd: like tEff but also filters fk Practitioner -- ADDITIVE metrics' targets follow the
// actual's real grain (blank at a site/practitioner with no entered target). Ratios keep tEff.
Func<string,string> tEffAdd = key => (@"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac   = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""{key}"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site,
    '_Effective Targets'[fk Practitioner]  = sel_prac)").Replace("{key}", key);

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
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
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
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
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
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
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
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
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
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
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
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
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
// Plan grain via Gold.Fact_Treatment_Plans ('_Treatment Plans'): the plan's OWN fk_Practitioner
// relationship drives the practitioner slicer -- no item routing. No ACTIVE date relationship on
// the fact, so the page/embed date slicer is ignored (current-state), no REMOVEFILTERS needed.
add("Treatment Acceptance Rate",
    @"DIVIDE(
    CALCULATE(
        SUM('_Treatment Plans'[Treatment Plan Count]),
        NOT ISBLANK('_Treatment Plans'[Start Date])
    ),
    SUM('_Treatment Plans'[Treatment Plan Count])
)",
    "#,##0.0%");

// Open courses: started-but-unfinished courses -- the plan has at least one COMPLETED item AND
// at least one OPEN item (Course Status In Progress | Open - No Appointment). Course Status
// (Gold.Fact_Treatment_Plans, item roll-up) already honours the plan-complete override (a plan
// marked complete is 'Complete' regardless of a stray open line). Plan grain via '_Treatment
// Plans' -- the plan's own fk_Practitioner drives the slicer and there is no active date
// relationship, so this is naturally current-state (date slicer ignored).
add("Open Courses",
    @"CALCULATE(
    COUNTROWS('_Treatment Plans'),
    '_Treatment Plans'[Course Status] IN { ""In Progress"", ""Open - No Appointment"" }
)",
    "#,##0");

// Open courses with no future appointment booked -- the leaky bucket. Read straight off the
// fact's Course Status (Has_Future_Appointment already resolved at build time: a non-cancelled
// appointment dated today-or-later). NO recency filter here -- we show ALL of them; the 3-month
// fresh/stale band is a separate DAX read off [Last Activity Date] so nothing is hidden.
add("Open Courses Without Appointment",
    @"CALCULATE(
    COUNTROWS('_Treatment Plans'),
    '_Treatment Plans'[Course Status] = ""Open - No Appointment""
)",
    "#,##0");

// Outstanding private value tied up in the leaky-bucket courses (started, unfinished, no future
// appointment). Private Treatment Value Outstanding = sum of open (NHS_Charge=0) item value,
// rolled up onto the plan. This is the "eye-watering" number for the review.
add("Open Courses Without Appointment Value",
    @"CALCULATE(
    SUM('_Treatment Plans'[Private Treatment Value Outstanding]),
    '_Treatment Plans'[Course Status] = ""Open - No Appointment""
)",
    "£#,##0");

// Exam ratio: exam appointments / all appointments
add("Exam Ratio",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[Exam Count]),
    SUM('Aggregate Site Patient Practitioner Daily'[Appointments]))",
    "#,##0.0%");

// Open Courses Value: outstanding private value across ALL open courses (In Progress +
// Open - No Appointment), read live off the plan-grain fact. Current-state by construction --
// the fact has no active date relationship, so the page/embed period slicer is ignored;
// practitioner slicer still applies (site is always -1 on the plan object).
add("Open Courses Value",
    @"CALCULATE(
    SUM('_Treatment Plans'[Private Treatment Value Outstanding]),
    '_Treatment Plans'[Course Status] IN { ""In Progress"", ""Open - No Appointment"" }
)",
    "£#,##0");

// Average private treatment value per started plan. Plan grain via '_Treatment Plans'
// (plan's own practitioner slicer, no active date relationship -> current-state).
add("Average Plan Value",
    @"DIVIDE(
    SUM('_Treatment Plans'[Private Treatment Value]),
    CALCULATE(
        COUNTROWS('_Treatment Plans'),
        NOT ISBLANK('_Treatment Plans'[Start Date])
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
kpi("Open Courses",                     "#,##0",    tEffAdd("open_courses"),               vPctGrey("Open Courses"),                        bgLowerEffGrey("Open Courses", "open_courses"));
kpi("Open Courses Without Appointment", "#,##0",    tEffAdd("open_courses_without_appt"),  vPctP("Open Courses Without Appointment"),       bgLowerEff("Open Courses Without Appointment", "open_courses_without_appt"));
kpi("Exam Ratio",                       "#,##0.0%", tEff100("exam_ratio"),              vPp("Exam Ratio"),                               bgWithinPp("Exam Ratio", "exam_ratio"));
kpi("Open Courses Value",               "£#,##0",   tEffAdd("open_courses_value"),         vPctGrey("Open Courses Value"),                  bgHigherEffGrey("Open Courses Value", "open_courses_value"));
kpi("Average Plan Value",               "£#,##0",   tEff("avg_plan_value"),             vPct("Average Plan Value"),                      bgHigherEff("Average Plan Value", "avg_plan_value"));

Info("Clinical KPI measures created (data-driven).");
