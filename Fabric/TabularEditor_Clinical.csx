// Clinical KPI measures — data-driven generation.
//
// Per-KPI Target / vs-Target / BG blocks are generated from per-KPI specs via the
// builder functions below. DAX is functionally identical to the previous
// hand-written version (DAX ignores whitespace). Value measures stay bespoke.
// All targets come from '_Daily Targets' (Fact_Daily_Targets), resolved by Target_Level.
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

// ── Target builders (target model: Fact_Daily_Targets, Target_Level resolution + FTE) ──
// lvl: practitioner in context -> their Custom Role; role selected -> that role; else Practice.
// FTE-scaled metrics multiply the per-FTE role target by SUM(FTE) of practitioners in context.
Func<string,string> fteMul = key => (key=="total_revenue"||key=="nhs_revenue"||key=="private_revenue"||key=="open_courses"||key=="open_courses_without_appt"||key=="open_courses_without_appt_value"||key=="open_courses_value") ? @" * IF(lvl = ""Practice"", 1, SUM('List Practitioners'[FTE]))" : "";

Func<string,string> tEff = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    MAX('_Daily Targets'[Annual Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
RETURN IF(ISBLANK(base_t), BLANK(), base_t{FTE})").Replace("{FTE}", fteMul(key)).Replace("{key}", key);

Func<string,string> tEff100 = key => tEff(key) + " / 100";

Func<string,string> tEffAdd = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    MAX('_Daily Targets'[Annual Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
RETURN IF(ISBLANK(base_t), BLANK(), base_t{FTE})").Replace("{FTE}", fteMul(key)).Replace("{key}", key);

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

// ── BG builders (target from [b Target]; band from _Daily Targets[Variance] at the resolved level) ─────────────────────────
Func<string,string,string> bgHigherEff = (b, key) => (@"VAR actual   = [{b}]
VAR lvl      = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Daily Targets'[Variance]), TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]), '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgHigherEffGrey = (b, key) => (@"VAR actual   = [{b}]
VAR lvl      = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Daily Targets'[Variance]), TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]), '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual), ""#E0E0E0"",
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerEff = (b, key) => (@"VAR actual   = [{b}]
VAR lvl      = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Daily Targets'[Variance]), TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]), '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerEffGrey = (b, key) => (@"VAR actual   = [{b}]
VAR lvl      = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Daily Targets'[Variance]), TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]), '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual), ""#E0E0E0"",
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgHigherPp = (b, key) => (@"VAR actual   = [{b}]
VAR lvl      = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Daily Targets'[Variance]), TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]), '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

// "within": deviation from target — being close is good (Exam Ratio)
Func<string,string,string> bgWithinPp = (b, key) => (@"VAR actual   = [{b}]
VAR lvl      = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Daily Targets'[Variance]), TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]), '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
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

kpi("Open Courses",                     "#,##0",    tEffAdd("open_courses"),               vPctGrey("Open Courses"),                        bgLowerEffGrey("Open Courses", "open_courses"));
kpi("Open Courses Without Appointment", "#,##0",    tEffAdd("open_courses_without_appt"),  vPctP("Open Courses Without Appointment"),       bgLowerEff("Open Courses Without Appointment", "open_courses_without_appt"));
// Tier-1 Home card: the £ value of the leaky bucket (started, unfinished, no future appt). Value
// measure defined above; lives off Gold.Fact_Treatment_Plans[Private Treatment Value Outstanding]
// (lit up by V064's tpi.Price fix). Lower is better (money committed but unscheduled -> book it).
kpi("Open Courses Without Appointment Value", "£#,##0", tEffAdd("open_courses_without_appt_value"), vPctGrey("Open Courses Without Appointment Value"), bgLowerEffGrey("Open Courses Without Appointment Value", "open_courses_without_appt_value"));
kpi("Exam Ratio",                       "#,##0.0%", tEff100("exam_ratio"),              vPp("Exam Ratio"),                               bgWithinPp("Exam Ratio", "exam_ratio"));
kpi("Open Courses Value",               "£#,##0",   tEffAdd("open_courses_value"),         vPctGrey("Open Courses Value"),                  bgHigherEffGrey("Open Courses Value", "open_courses_value"));
kpi("Average Plan Value",               "£#,##0",   tEff("avg_plan_value"),             vPct("Average Plan Value"),                      bgHigherEff("Average Plan Value", "avg_plan_value"));

Info("Clinical KPI measures created (data-driven).");
