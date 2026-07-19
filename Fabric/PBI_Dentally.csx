// PBI_Dentally.csx -- ALL measures for PBI Dentally.pbix, one atomic apply.
// Amalgamated from the former per-section TabularEditor_*.csx; each section wrapped in its own
// scope block { } so local helpers do not collide. ONE paste, ONE Run rebuilds every folder;
// measures keep exact names + DisplayFolder so report cards re-bind automatically.
// (Dead spider measures are purged separately by TabularEditor_KillDeadSpiders.csx -- run once.)

// ===================== AppointmentJourney =====================
{
// =====================================================================
// Appointment Journey -- model side for the SCALABLE (Gold-view-backed) Alluvial
// =====================================================================
// The journey is now PRECOMPUTED in Gold and exposed as a mode-long view:
//   Gold.Fact_Appointment_Journey      -- appt-grain base, 4 next-pointers, full rebuild
//   Gold.vw_Fact_Appointment_Journey   -- one row per (appt x qualifying mode),
//                                         Delay / Next Appointment / Current State as COLUMNS
//   PBI.[_Appointment Journey]         -- the presentation view (import into the model)
//
// Because the stages are COLUMNS (not dynamic measures) and 'Mode' is a real column,
// Power BI aggregates server-side and Deneb only ever receives the distinct
// stage-combinations -- so the Alluvial scales to any tenant volume (no 30k data cap).
//
// This RETIRES the old dynamic approach: the per-appointment look-ahead measures
// (Delay / Next Appointment / Current State / Next Appt Start / Journey Current
// Matches / Journey Count gate) and the disconnected 'Journey Filter' slicer are
// gone. The only measure left is a plain COUNT weight.
//
// ORDER: import the '_Appointment Journey' table FIRST, then run this, then Save.
// =====================================================================

var jmTable  = Model.Tables["_Measures"];
var jmFolder = "Appointment Journey";

// Retire every old Appointment Journey measure (the dynamic look-ahead set).
foreach (var existing in jmTable.Measures.Where(x => x.DisplayFolder == jmFolder).ToList())
    existing.Delete();

// Single weight: one row per appointment in the (mode-filtered) view. The mode gate
// is baked into the view, so this is an un-gated plain count.
var jc = jmTable.AddMeasure("Journey Count", "COUNTROWS('_Appointment Journey')");
jc.DisplayFolder = jmFolder;
jc.FormatString  = "#,##0";

Info(
    "Appointment Journey: retired the old dynamic measures; added [Journey Count] = " +
    "COUNTROWS('_Appointment Journey').\n" +
    "MANUAL (step 4): (1) import PBI.[_Appointment Journey]; (2) point the Deneb Alluvial " +
    "at its columns Booking / Appointment Reason / Delay / Next Appointment / Current State " +
    "+ the [Journey Count] measure (NO bk Appointment ID); (3) put '_Appointment Journey'[Mode] " +
    "on the slicer and DELETE the old disconnected 'Journey Filter' table; (4) publish."
);
}

// ===================== Clinical =====================
{
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
    ISBLANK(actual) || ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPctP = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(actual) || ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPctGrey = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(actual) || ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPp = b => (@"VAR actual  = [{b}]
VAR target  = [{b} Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(actual) || ISBLANK(target), BLANK(),
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
    ISBLANK(target), ""#FFFFFF"",
    ISBLANK(actual), ""#E0E0E0"",
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
    ISBLANK(target), ""#FFFFFF"",
    ISBLANK(actual), ""#E0E0E0"",
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
}

// ===================== Finance =====================
{
// Finance / margin measures — Net Profit + EBITDA from the Xero P&L fact.
//
// Reads '_Finance' (Gold.Fact_Finance) classified by GL account P&L group on
// 'List GL Account' (Gold.Dim_GL_Account):
//   PL Group in { Income | Cost of Sales | Operating Expenses | Depreciation | Finance Costs }
//   EBITDA Item = 0 for depreciation/amortisation + interest/finance (excluded from EBITDA).
// PL Amount is the signed P&L contribution (revenue +, expense +), so:
//   Net Profit = Income - all costs;  EBITDA = Income - operating costs (adds back D&A + interest).
//
// Requires the '_Finance' + 'List GL Account' tables in the model (PBI views
// PBI._Finance / PBI.List GL Account). Tabular Editor C#: no string interpolation,
// DAX is verbatim @"..." strings.

var t = Model.Tables["_Measures"];
var g = "Finance KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

string CUR = "#,##0;(#,##0)";
string PCT = "0.0%";

// ── Components ────────────────────────────────────────────────────────────────
add("Total Revenue (PL)",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] = ""Income"")", CUR);

add("Cost of Sales",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] = ""Cost of Sales"")", CUR);

add("Operating Expenses",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] = ""Operating Expenses"")", CUR);

add("Operating Costs",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] IN {""Cost of Sales"", ""Operating Expenses""})", CUR);

add("Depreciation & Interest",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] IN {""Depreciation"", ""Finance Costs""})", CUR);

add("Total Costs",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] <> ""Income"")", CUR);

// ── Headline profitability ────────────────────────────────────────────────────
add("EBITDA",     @"[Total Revenue (PL)] - [Operating Costs]", CUR);
add("Net Profit", @"[Total Revenue (PL)] - [Total Costs]",     CUR);

add("EBITDA Margin %", @"DIVIDE([EBITDA], [Total Revenue (PL)])",     PCT);
add("Net Margin %",    @"DIVIDE([Net Profit], [Total Revenue (PL)])", PCT);

Info("Finance KPIs created: Total Revenue, Cost of Sales, Operating Expenses, Operating Costs, "
   + "Depreciation & Interest, Total Costs, EBITDA, Net Profit, EBITDA Margin %, Net Margin %.");
}

// ===================== KPI_Snapshot =====================
{
var t = Model.Tables["_Measures"];
var g = "Clinical KPIs";

// (no delete-loop: Clinical already cleared the shared 'Clinical KPIs' folder above)

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Open Courses Value ─────────────────────────────────────────────────
// The current-state CARD "Open Courses Value" is now owned by TabularEditor_Clinical.csx
// (live off Gold.Fact_Treatment_Plans -> [Private Treatment Value Outstanding], the item
// roll-up). It is NOT defined here any more -- both scripts share the "Clinical KPIs"
// folder + delete-first, so defining it in both made the card depend on run order.
//
// This script keeps the HISTORICAL series only (Trend / Target / vs / BG). NB: the snapshot
// history was captured under the OLD open_courses_value definition, so the Trend line and the
// live card measure are not strictly like-for-like until the snapshot metric is rebuilt.
// Trend measure — plain SUM: the date-axis context in a chart already restricts
//                 to a single snapshot date per point; add a visual filter
//                 Snapshot Grain = "monthly" for clean month-end series.

add("Open Courses Value Trend",
    @"CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[Metric] = ""open_courses_value""
)",
    "£#,##0");

// Target / vs Target / BG for "Open Courses Value" are owned by the Clinical block above
// (kpi("Open Courses Value", ...) -> target-model, FTE-aware, off _Daily Targets). Defining
// them here too created DUPLICATE measure names in the amalgamated file (both blocks share the
// "Clinical KPIs" folder), which poisoned resolution of [Open Courses Value] / [Average Plan
// Value]. KPI_Snapshot keeps ONLY the historical Trend series.

Info("Clinical KPI snapshot Trend created.");
}

// ===================== MetricActuals =====================
{
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
VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR use_practice = (sel_prac = -1) && (lvl = ""Practice"")
VAR pracf = FILTER(ALL('_Metric Actuals'[fk Practitioner]), IF(use_practice, '_Metric Actuals'[fk Practitioner] = -1, '_Metric Actuals'[fk Practitioner] IN VALUES('List Practitioners'[pk Practitioner])))
RETURN
CALCULATE(
    SUM('_Metric Actuals'[Numerator]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric]           = ""{key}"",
    '_Metric Actuals'[fk Practice Site] = sel_site,
    pracf
)").Replace("{key}", key);

// Rate over the date context: DIVIDE(sum num, sum den).
Func<string,string> dRate = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR use_practice = (sel_prac = -1) && (lvl = ""Practice"")
VAR pracf = FILTER(ALL('_Metric Actuals'[fk Practitioner]), IF(use_practice, '_Metric Actuals'[fk Practitioner] = -1, '_Metric Actuals'[fk Practitioner] IN VALUES('List Practitioners'[pk Practitioner])))
VAR n = CALCULATE( SUM('_Metric Actuals'[Numerator]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, pracf )
VAR d = CALCULATE( SUM('_Metric Actuals'[Denominator]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, pracf )
RETURN DIVIDE(n, d)").Replace("{key}", key);

// Snapshot stock: latest snapshot date in the selected period, then the value at it.
Func<string,string> dSnap = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR use_practice = (sel_prac = -1) && (lvl = ""Practice"")
VAR pracf = FILTER(ALL('_Metric Actuals'[fk Practitioner]), IF(use_practice, '_Metric Actuals'[fk Practitioner] = -1, '_Metric Actuals'[fk Practitioner] IN VALUES('List Practitioners'[pk Practitioner])))
VAR snap_fk = CALCULATE( MAX('_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, pracf )
RETURN CALCULATE( SUM('_Metric Actuals'[Numerator]),
    '_Metric Actuals'[fk Date] = snap_fk,
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, pracf )").Replace("{key}", key);

// Current-state value: ONE row per grain, read date-blind (period-independent).
Func<string,string> dCur = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR use_practice = (sel_prac = -1) && (lvl = ""Practice"")
VAR pracf = FILTER(ALL('_Metric Actuals'[fk Practitioner]), IF(use_practice, '_Metric Actuals'[fk Practitioner] = -1, '_Metric Actuals'[fk Practitioner] IN VALUES('List Practitioners'[pk Practitioner])))
RETURN CALCULATE( SUM('_Metric Actuals'[Numerator]),
    REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, pracf )").Replace("{key}", key);

// Current-state rate: date-blind DIVIDE. currate metrics are all practitioner-AGNOSTIC (stored at
// fk Practitioner = -1 only), so pin to -1 and IGNORE the practitioner slicer -> shows the global
// value (greyed by the GreyP variance) instead of blanking to "No data" when a practitioner is picked.
Func<string,string> dCurRate = key => (@"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR n = CALCULATE( SUM('_Metric Actuals'[Numerator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
VAR d = CALCULATE( SUM('_Metric Actuals'[Denominator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""{key}"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
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
    // Overdue Recalls is practitioner-agnostic but 'cur' also serves practitioner-supporting metrics
    // (days_until_*), so it is NOT retargeted here -- its bespoke measure in Patients.csx pins fk
    // Practitioner = -1 (global, greyed) directly.
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
}

// ===================== NHS =====================
{
var t = Model.Tables["_Measures"];
var g = "NHS KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Value measures ───────────────────────────────────────────────────────────
// Note: NHS metrics are not in Config.Metric_Definitions and have no
// _Targets backing, so BG measures return white until targets are added.

add("NHS UDAs",
    @"SUM('Aggregate Site Patient Practitioner Daily'[NHS UDAs])",
    "#,##0.00");

add("NHS UOAs",
    @"SUM('Aggregate Site Patient Practitioner Daily'[NHS UOAs])",
    "#,##0.00");

// ── CONTRACT cards (the headline NHS targets vs delivery) ─────────────────────
// "Contracted" IS the contract target -- identical to [NHS UDA Annual Target] (the
// practice contract at the -1 level; the SELECTED practitioner's individual contract
// when one is chosen). "Completed" is what was actually delivered against it (claimed
// UDAs). One source of truth: these alias the canonical contract measures below.
// NOTE: per-practitioner contract targets only exist where loaded (tenant 11: FY26-27
// only); selecting a practitioner in a year with no individual target shows blank.
add("NHS UDA Contracted",       @"[NHS UDA Annual Target]",       "#,##0");
add("NHS UDA Completed",        @"[NHS UDA Delivered]",           "#,##0");
// Judge delivery against where we SHOULD be by now ([Target To Date]), NOT the full
// annual target. Against the annual figure the LIVE year reads ~16% mid-way and the 95%
// band paints it red all year. [Target To Date] = the full annual once the FY is over, so
// COMPLETED years are unchanged (rate = true completion %); the LIVE year reads as PACE
// (~100% = on track) and the within-band colour judges it correctly. Raw year-to-date
// progress is still available as [NHS UDA % of Annual Target] if you want to show it too.
add("NHS UDA Completion Rate",  @"DIVIDE([NHS UDA Delivered], [NHS UDA Target To Date])",  "#,##0.0%");

// ── PLAN-completion family (CLINICAL, optional -- from Fact_Treatment_Plans) ──
// SEPARATE from the contract: UDA scheduled vs completed on treatment plans, FY-scoped
// by the plan's START date via USERELATIONSHIP (the fact's date relationship is inactive
// per V019). Use only if you want a clinical plan view alongside the contract cards;
// these will NOT equal the contract figures.
// PREREQUISITE: '_Treatment Plans' imported with an (inactive) fk Date Start ->
// 'List Date'[pk Date] relationship, or these error.
add("NHS Plan UDA Scheduled",
    @"VAR _today = TODAY()
VAR _curFy = IF(MONTH(_today) >= 4, YEAR(_today), YEAR(_today) - 1)
VAR _fy    = SELECTEDVALUE('List Date'[Financial Year], _curFy)
RETURN
CALCULATE(
    SUM('_Treatment Plans'[NHS UDA Value]),
    USERELATIONSHIP('_Treatment Plans'[fk Date Start], 'List Date'[pk Date]),
    REMOVEFILTERS('List Date'),
    FILTER(ALL('List Date'), 'List Date'[Financial Year] = _fy))",
    "#,##0");

add("NHS Plan UDA Completed",
    @"VAR _today = TODAY()
VAR _curFy = IF(MONTH(_today) >= 4, YEAR(_today), YEAR(_today) - 1)
VAR _fy    = SELECTEDVALUE('List Date'[Financial Year], _curFy)
RETURN
CALCULATE(
    SUM('_Treatment Plans'[NHS Completed UDA Value]),
    USERELATIONSHIP('_Treatment Plans'[fk Date Start], 'List Date'[pk Date]),
    REMOVEFILTERS('List Date'),
    FILTER(ALL('List Date'), 'List Date'[Financial Year] = _fy))",
    "#,##0");

add("NHS Plan UDA Completion Rate",
    @"DIVIDE([NHS Plan UDA Completed], [NHS Plan UDA Scheduled])",
    "#,##0.0%");

// NHS Revenue is defined in the Revenue KPIs folder; reference it here for
// convenience on the NHS report page without duplicating the formula.
// If you need a standalone copy, uncomment and rename below.
// add("NHS Revenue (NHS)", @"[NHS Revenue]", ""£#,##0"");

// ── Claims by their OWN date (role-playing date, NOT a duplicated fact) ───────
// '_NHS Claims' has TWO dates: fk Date Submitted (the ACTIVE relationship to List
// Date) and fk Date Approval. To plot Awarded by its approval date while Expected
// stays on the submission date, add ONE inactive relationship in the model:
//     '_NHS Claims'[fk Date Approval] -> 'List Date'[pk Date]   (set INACTIVE)
// then these measures pick the right date per series via USERELATIONSHIP. No second
// copy of the fact, no extra RLS. (Un-awarded claims have no approval date, so they
// correctly drop off the Awarded-by-approval line.)
// NB: these two measures will ERROR until that inactive relationship exists — add it
// BEFORE running this script.
add("NHS UDA Expected (submitted)",
    @"SUM('_NHS Claims'[Expected UDA])",
    "#,##0.00");

add("NHS UDA Awarded (approved)",
    @"CALCULATE(
    SUM('_NHS Claims'[Awarded UDA]),
    USERELATIONSHIP('_NHS Claims'[fk Date Approval], 'List Date'[pk Date]))",
    "#,##0.00");

// ── FY YTD measures ──────────────────────────────────────────────────────────
// NHS contracts run April -> March. These measures lock to the current FY
// regardless of any date slicer selection, so the NHS page always shows
// in-year progress without requiring a specific date grouping to be selected.

add("NHS UDA Contracted FY",
    @"VAR today    = TODAY()
VAR fy_start = IF(MONTH(today) >= 4, DATE(YEAR(today), 4, 1), DATE(YEAR(today)-1, 4, 1))
VAR fy_end   = DATE(YEAR(fy_start)+1, 3, 31)
RETURN
CALCULATE(
    SUM('List Treatment Plans'[NHS UDA Value]),
    'List Treatment Plans'[Start Date] >= fy_start,
    'List Treatment Plans'[Start Date] <= fy_end)",
    "#,##0.00");

add("NHS UDA Completed FY YTD",
    @"VAR today    = TODAY()
VAR fy_start = IF(MONTH(today) >= 4, DATE(YEAR(today), 4, 1), DATE(YEAR(today)-1, 4, 1))
RETURN
CALCULATE(
    SUM('List Treatment Plans'[NHS Completed UDA Value]),
    'List Treatment Plans'[Completed] = TRUE(),
    'List Treatment Plans'[Completed Date] >= fy_start,
    'List Treatment Plans'[Completed Date] <= today)",
    "#,##0.00");

add("NHS UDA Completion Rate FY YTD",
    @"DIVIDE([NHS UDA Completed FY YTD], [NHS UDA Contracted FY])",
    "#,##0.0%");

// ── Target and variance measures ─────────────────────────────────────────────

add("NHS UDAs Target",
    @"VAR full_target = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric]       = ""nhs_udas"",
    '_Daily Targets'[Target Level] = ""Practice"")
RETURN IF(ISBLANK(full_target), BLANK(), full_target)",
    "#,##0.00");

add("NHS UDAs vs Target",
    @"VAR actual = [NHS UDAs]
VAR target = [NHS UDAs Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("NHS UOAs Target",
    @"VAR full_target = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric]       = ""nhs_uoas"",
    '_Daily Targets'[Target Level] = ""Practice"")
RETURN IF(ISBLANK(full_target), BLANK(), full_target)",
    "#,##0.00");

add("NHS UOAs vs Target",
    @"VAR actual = [NHS UOAs]
VAR target = [NHS UOAs Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

// Target lookup: nhs_uda_completion_rate target now from '_Daily Targets' (Fact_Daily_Targets),
// rows carry fk Date = -1, so the page's Period (FY) slicer empties the table through
// that relationship. REMOVEFILTERS the date/site/practitioner so it can't, and KEEP RLS
// for the tenant (don't depend on SELECTEDVALUE('List Practice Sites'[Tenant ID]),
// which is blank when the sites dim isn't RLS-filtered). Value is stored as a whole
// percent (95) -> /100.
add("NHS UDA Completion Rate Target",
    @"DIVIDE(
    CALCULATE(
        MAX('_Daily Targets'[Annual Target Value]),
        REMOVEFILTERS('List Date'),
        REMOVEFILTERS('List Practice Sites'),
        REMOVEFILTERS('List Practitioners'),
        '_Daily Targets'[Metric]           = ""nhs_uda_completion_rate"",
        '_Daily Targets'[Target Level] = ""Practice""),
    100)",
    "#,##0.0%");

add("NHS UDA Completion Rate vs Target",
    @"VAR actual  = [NHS UDA Completion Rate]
VAR target  = [NHS UDA Completion Rate Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

// ═════════════════════════════════════════════════════════════════════════════
//  NHS ANNUAL CONTRACT TRACKING  (UDA)
// ─────────────────────────────────────────────────────────────────────────────
//  Two consistent sources, used by EVERY measure in this section:
//    • TARGET  = '_NHS Contract Week'[Pro Rata UDA Target]  (annual contract UDA
//                target pro-rated across the Apr->Mar financial weeks by working
//                days). Practitioner-aware via [fk Practitioner] = SELECTEDVALUE(...):
//                the PRACTICE contract (level -1) when no single practitioner is
//                selected, the practitioner's INDIVIDUAL allocation when one is. Never
//                sums both levels (which would double-count). Requires the two-level
//                Fact_NHS_Contract_Week (*02) to be deployed.
//    • ACTUAL  = '_NHS Claims'  COALESCE(Awarded UDA, Expected UDA)  (UDAs that
//                have actually been claimed; awarded where settled, else expected).
//
//  MODEL PREREQUISITES (must be true in the semantic model or these blank):
//    1. '_NHS Contract Week' table imported (PBI.[_NHS Contract Week]) WITH the
//       fk Practitioner / fk Practice Site columns from the *02 view.
//    2. '_NHS Contract Week'[fk Date Week Start] -> 'List Date'[pk Date] relationship.
//    3. '_NHS Claims' related to 'List Date' on the date you want UDAs counted by
//       (submission date is the usual choice for contract delivery).
//    4. RLS [Tenant ID] on '_NHS Contract Week'.
//
//  The cards (Annual Target / Delivered / Target To Date / %) RESPECT the Financial
//  Year selected on the page's Period slicer (falling back to the current FY when
//  none/many are selected) AND the selected practitioner. So the cards reconcile with
//  the cumulative line pair for whatever FY you're viewing: for a completed past FY the
//  cards show the full-year actuals; for the live FY they show progress to date.
// ═════════════════════════════════════════════════════════════════════════════

// ── Headline cards: where are we vs the whole-year target ────────────────────
// All resolve the financial year from the Period slicer; if none/many selected
// they fall back to the current FY. Contract target = '_NHS Contract Week' level
// -1; actual = '_NHS Claims'. These reconcile with the cumulative line pair.

// Full-year contract target for the selected FY (sum of weekly pro-rata = annual).
// Practitioner-aware: the PRACTICE contract (level -1) when no single practitioner is
// selected; that practitioner's INDIVIDUAL contract allocation when one is selected.
add("NHS UDA Annual Target",
    @"VAR _today   = TODAY()
VAR _curFy   = IF(MONTH(_today) >= 4, YEAR(_today), YEAR(_today) - 1)
VAR _fy      = SELECTEDVALUE('List Date'[Financial Year], _curFy)
VAR _selPrac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN
CALCULATE(
    SUM('_NHS Contract Week'[Pro Rata UDA Target]),
    REMOVEFILTERS('List Date'),
    '_NHS Contract Week'[Financial Year]   = _fy,
    '_NHS Contract Week'[fk Practitioner]  = _selPrac)",
    "#,##0");

// UDAs claimed in the selected FY (full year for a past FY; to-date for the live FY,
// since no future claims exist yet).
add("NHS UDA Delivered",
    @"VAR _today = TODAY()
VAR _curFy = IF(MONTH(_today) >= 4, YEAR(_today), YEAR(_today) - 1)
VAR _fy    = SELECTEDVALUE('List Date'[Financial Year], _curFy)
RETURN
CALCULATE(
    SUMX('_NHS Claims', COALESCE('_NHS Claims'[Awarded UDA], '_NHS Claims'[Expected UDA])),
    REMOVEFILTERS('List Date'),
    FILTER(ALL('List Date'), 'List Date'[Financial Year] = _fy))",
    "#,##0");

// Where we SHOULD be by now. Past FY -> full annual (year is over). Live FY ->
// pro-rata accumulated to today's week. Future FY -> 0.
add("NHS UDA Target To Date",
    @"VAR _today   = TODAY()
VAR _curFy   = IF(MONTH(_today) >= 4, YEAR(_today), YEAR(_today) - 1)
VAR _fy      = SELECTEDVALUE('List Date'[Financial Year], _curFy)
VAR _selPrac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR _curWeek = MAXX(FILTER(ALL('List Date'), 'List Date'[Full Date] = _today), 'List Date'[Financial Week])
VAR _weekCap = IF(_fy < _curFy, 60, IF(_fy > _curFy, 0, _curWeek))
RETURN
CALCULATE(
    SUM('_NHS Contract Week'[Pro Rata UDA Target]),
    REMOVEFILTERS('List Date'),
    '_NHS Contract Week'[Financial Year]   = _fy,
    '_NHS Contract Week'[Financial Week]  <= _weekCap,
    '_NHS Contract Week'[fk Practitioner]  = _selPrac)",
    "#,##0");

// Progress through the whole-year contract target (e.g. 62%).
add("NHS UDA % of Annual Target",
    @"DIVIDE([NHS UDA Delivered], [NHS UDA Annual Target])",
    "#,##0.0%");

// Pace: UDAs ahead (+) / behind (-) the where-we-should-be figure.
add("NHS UDA Pace (UDAs)",
    @"VAR _d = [NHS UDA Delivered]
VAR _t = [NHS UDA Target To Date]
RETURN IF(ISBLANK(_t), BLANK(), _d - _t)",
    "+#,##0;-#,##0");

// Pace as a %: +5% = 5% ahead of schedule, -8% = 8% behind.
add("NHS UDA Pace %",
    @"VAR _d = [NHS UDA Delivered]
VAR _t = [NHS UDA Target To Date]
RETURN IF(ISBLANK(_t) || _t = 0, BLANK(), DIVIDE(_d - _t, _t))",
    "+#,##0.0%;-#,##0.0%");

// On-track flag colour for a pace card (green ahead / amber slightly behind / red).
add("NHS UDA Pace BG",
    @"VAR _p = [NHS UDA Pace %]
RETURN SWITCH(TRUE(),
    ISBLANK(_p),    ""#FFFFFF"",
    _p >= 0,        ""#1a7f3c"",
    _p >= -0.05,    ""#f4a261"",
                    ""#c0392b"")",
    "");

// ── Cumulative line-chart series (X = List Date[Week Commencing Date]) ────────
// Put a single Financial Year slicer on the page; both series accumulate
// week-by-week within whatever FY is selected (default current FY).

// Cap at "now": blank any week AFTER today so the YTD line ends at today rather than
// flat-lining to year-end. Past FYs are unaffected (every week is before today).
add("NHS UDA Delivered Cumulative",
    @"VAR _today  = TODAY()
VAR _curFy  = IF(MONTH(_today) >= 4, YEAR(_today), YEAR(_today) - 1)
VAR _curWk  = MAXX(FILTER(ALL('List Date'), 'List Date'[Full Date] = _today), 'List Date'[Financial Week])
VAR _fy     = MAX('List Date'[Financial Year])
VAR _fw     = MAX('List Date'[Financial Week])
VAR _future = _fy > _curFy || (_fy = _curFy && _fw > _curWk)
RETURN
IF(_future, BLANK(),
CALCULATE(
    SUMX('_NHS Claims', COALESCE('_NHS Claims'[Awarded UDA], '_NHS Claims'[Expected UDA])),
    REMOVEFILTERS('List Date'),
    FILTER(ALL('List Date'),
        'List Date'[Financial Year] = _fy && 'List Date'[Financial Week] <= _fw)))",
    "#,##0");

// Cap at "now" the same way as the delivered series, so the two YTD lines terminate
// together at today. Past FYs show the full year; future weeks of the live FY are blank.
add("NHS UDA Target Cumulative",
    @"VAR _today   = TODAY()
VAR _curFy   = IF(MONTH(_today) >= 4, YEAR(_today), YEAR(_today) - 1)
VAR _curWk   = MAXX(FILTER(ALL('List Date'), 'List Date'[Full Date] = _today), 'List Date'[Financial Week])
VAR _fy      = MAX('List Date'[Financial Year])
VAR _fw      = MAX('List Date'[Financial Week])
VAR _future  = _fy > _curFy || (_fy = _curFy && _fw > _curWk)
VAR _selPrac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN
IF(_future, BLANK(),
CALCULATE(
    SUM('_NHS Contract Week'[Pro Rata UDA Target]),
    REMOVEFILTERS('List Date'),
    '_NHS Contract Week'[Financial Year]   = _fy,
    '_NHS Contract Week'[Financial Week]  <= _fw,
    '_NHS Contract Week'[fk Practitioner]  = _selPrac))",
    "#,##0");

// ── BG colour measures ───────────────────────────────────────────────────────
// nhs_udas / nhs_uoas: target and band from _Daily Targets (contract-derived).
// nhs_uda_completion_rate: target and band from _Targets (manual Input.Targets entry).

add("NHS UDAs BG",
    @"VAR actual     = [NHS UDAs]
VAR target     = [NHS UDAs Target]
VAR band       = CALCULATE(
    MAX('_Daily Targets'[Variance]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric]       = ""nhs_udas"",
    '_Daily Targets'[Target Level] = ""Practice"")
VAR pct        = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct >= band,       ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,      ""#f4a261"",
                       ""#c0392b"")",
    "");

add("NHS UOAs BG",
    @"VAR actual     = [NHS UOAs]
VAR target     = [NHS UOAs Target]
VAR band       = CALCULATE(
    MAX('_Daily Targets'[Variance]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric]       = ""nhs_uoas"",
    '_Daily Targets'[Target Level] = ""Practice"")
VAR pct        = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct >= band,       ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,      ""#f4a261"",
                       ""#c0392b"")",
    "");

// NHS UDA delivery is a 'within' metric (Config.Metric_Definitions Range_Type='within'),
// NOT higher-is-better: 95% is the target, the NHS doesn't penalise 95%+, and you don't
// want to overshoot (>100% is unpaid work). So colour by DEVIATION from target in either
// direction (same as exam_ratio's bgWithinPp), with the band = '_Daily Targets'[Variance] (pp).
add("NHS UDA Completion Rate BG",
    @"VAR actual = [NHS UDA Completion Rate]
VAR target = [NHS UDA Completion Rate Target]
VAR band   = CALCULATE(
    MAX('_Daily Targets'[Variance]),
    REMOVEFILTERS('List Date'),
    REMOVEFILTERS('List Practice Sites'),
    REMOVEFILTERS('List Practitioners'),
    '_Daily Targets'[Metric]           = ""nhs_uda_completion_rate"",
    '_Daily Targets'[Target Level] = ""Practice"")
VAR dev    = ABS((actual - target) * 100)
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    dev <= band,     ""#1a7f3c"",
    dev <= band * 2, ""#6abf7b"",
    dev <= band * 3, ""#f4a261"",
                     ""#c0392b"")",
    "");

Info("NHS KPI measures created.");
}

// ===================== PatientCohorts =====================
{
var t = Model.Tables["_Measures"];
var g = "Patient Cohorts";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// Distinct patients meeting a condition, counted ONCE. Pattern:
//   CALCULATE(DISTINCTCOUNT(fact[fk Patient]), <pre-computed flag>)
// The flags are BIT columns computed in the Gold load (Is_Discount /
// Is_Invoice_Outstanding on Fact_Invoice_Items, Is_Deposit on Fact_Payments,
// Is_Email_Missing / Is_Phone_Missing on Dim_Patients), so the DAX stays a
// one-line CALCULATE rather than complex logic or wide per-condition FK columns.

// -- Financial cohorts: distinct patients tied to an invoice/payment condition --

add("Patients With Discount",
    @"CALCULATE(DISTINCTCOUNT('_Invoice Items'[fk Patient]), 'List Invoices'[Is Discount] = TRUE())",
    "#,##0");

add("Patients With Outstanding Invoice",
    @"CALCULATE(DISTINCTCOUNT('_Invoices'[fk Patient]), '_Invoices'[Is Invoice Outstanding] = TRUE())",
    "#,##0");

add("Patients With Deposit",
    @"CALCULATE(DISTINCTCOUNT('_Payments'[fk Patient]), '_Payments'[Is Deposit] = TRUE())",
    "#,##0");

// -- Reception data-capture gaps --
// Distinct patients who ATTENDED (Is Arrived) but still lack the detail. Counted
// once per patient; period/site/practitioner-aware via the appointment fact;
// excludes never-attended patients (no capture opportunity) and DNAs/cancellations.

add("Patients Email Not Captured",
    @"CALCULATE(
    DISTINCTCOUNT('_Appointments'[fk Patient]),
    'List Patients'[Is Email Missing] = TRUE(),
    '_Appointments'[Is Arrived] = TRUE())",
    "#,##0");

add("Patients Phone Not Captured",
    @"CALCULATE(
    DISTINCTCOUNT('_Appointments'[fk Patient]),
    'List Patients'[Is Phone Missing] = TRUE(),
    '_Appointments'[Is Arrived] = TRUE())",
    "#,##0");

Info("Patient Cohort measures created.");
}

// ===================== Patients =====================
{
// Patient KPI measures — data-driven generation.
//
// Per-KPI Target / vs-Target / BG blocks (~40 lines each) are generated from
// per-KPI specs via the builder functions below. DAX is functionally identical to
// the previous hand-written version (DAX ignores whitespace). Value measures stay
// bespoke. All targets come from '_Daily Targets' (Fact_Daily_Targets), resolved by Target_Level.
//
// NOTE: Tabular Editor's C# has no string interpolation (dollar-prefixed strings),
// so templates are verbatim @"..." with {b}/{key} placeholders filled via .Replace().
//
// Builder variants on this page (named explicitly so each is a faithful copy):
//   Target : tEff (plain) | tEffRunRate (count metrics x run rate) | tEff100 (ratios, /100)
//   vs     : vPct | vPctP (+prefix) | vPctGreyP (+No-data +prefix)
//            vPp  | vPpP  (+prefix)  | vPpGreyP  (+No-data +prefix)
//   BG     : bgHigherEff | bgHigherEffGrey | bgLowerEffGrey
//            bgHigherPp   | bgHigherPpGrey  | bgLowerPp
// ("prefix" = the "⚠ " shown when a practitioner slicer is active on a
//  Supports_Practitioner = 0 metric.)

var t = Model.Tables["_Measures"];
var g = "Patients KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Target builders (target model: Fact_Daily_Targets, Target_Level resolution + FTE) ──
// lvl: practitioner in context -> Custom Role; role -> that role; else Practice. RunRate/tDaily
// variants sum the daily-apportioned fact over the selected period (proration is inherent).
Func<string,string> fteMul = key => (key=="total_revenue"||key=="nhs_revenue"||key=="private_revenue"||key=="open_courses"||key=="open_courses_without_appt"||key=="open_courses_without_appt_value"||key=="open_courses_value") ? @" * IF(lvl = ""Practice"", 1, SUM('List Practitioners'[FTE]))" : "";

Func<string,string> tEff = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    MAX('_Daily Targets'[Annual Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
RETURN IF(ISBLANK(base_t), BLANK(), base_t{FTE})").Replace("{FTE}", fteMul(key)).Replace("{key}", key);

Func<string,string> tEffRunRate = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
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

Func<string,string> tEffRunRateAdd = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
RETURN IF(ISBLANK(base_t), BLANK(), base_t{FTE})").Replace("{FTE}", fteMul(key)).Replace("{key}", key);

Func<string,string> tDaily = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
RETURN IF(ISBLANK(base_t), BLANK(), base_t{FTE})").Replace("{FTE}", fteMul(key)).Replace("{key}", key);

// ── vs-Target builders ───────────────────────────────────────────────────────
Func<string,string> vPct = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(actual) || ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPctP = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(actual) || ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPctGreyP = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(actual) || ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPp = b => (@"VAR actual  = [{b}]
VAR target  = [{b} Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))").Replace("{b}", b);

Func<string,string> vPpP = b => (@"VAR actual  = [{b}]
VAR target  = [{b} Target]
VAR diff_pp = (actual - target) * 100
VAR prefix  = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))").Replace("{b}", b);

Func<string,string> vPpGreyP = b => (@"VAR actual  = [{b}]
VAR target  = [{b} Target]
VAR diff_pp = (actual - target) * 100
VAR prefix  = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(actual) || ISBLANK(target), BLANK(),
    prefix & IF(diff_pp >= 0,
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
    ISBLANK(target), ""#FFFFFF"",
    ISBLANK(actual), ""#E0E0E0"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerEffGrey = (b, key) => (@"VAR actual   = [{b}]
VAR lvl      = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Daily Targets'[Variance]), TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]), '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    ISBLANK(actual), ""#E0E0E0"",
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

Func<string,string,string> bgHigherPpGrey = (b, key) => (@"VAR actual   = [{b}]
VAR lvl      = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Daily Targets'[Variance]), TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]), '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    ISBLANK(actual),  ""#E0E0E0"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerPp = (b, key) => (@"VAR actual   = [{b}]
VAR lvl      = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Daily Targets'[Variance]), TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]), '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp <= -band, ""#1a7f3c"",
    diff_pp <= 0,     ""#6abf7b"",
    diff_pp <= band,  ""#f4a261"",
                      ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Action<string,string,string,string,string> kpi = (baseName, fmt, targetDax, vsDax, bgDax) => {
    add(baseName + " Target",    targetDax, fmt);
    add(baseName + " vs Target", vsDax,     "");
    add(baseName + " BG",        bgDax,     "");
};

// ── Value measures (bespoke) ─────────────────────────────────────────────────

add("New Patients",
    @"CALCULATE(
    DISTINCTCOUNT('Aggregate Site Patient Practitioner Daily'[fk Patient]),
    'Aggregate Site Patient Practitioner Daily'[New Patient] = TRUE())",
    "#,##0");

// Lapsed = a FLOW metric (V050): read the AGG ('_Metric Actuals' -- a fact PROPERLY related to
// List Date), SUMmed over the period via TREATAS. NO dim-to-dim relationship. Total + two disjoint
// cohorts. This is the 'cum' shape; TabularEditor_MetricActuals.csx apply-mode sets the same in place.
add("Lapsed Patients",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN CALCULATE(
    SUM('_Metric Actuals'[Numerator]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric]           = ""lapsed_patients"",
    '_Metric Actuals'[fk Practice Site] = sel_site,
    '_Metric Actuals'[fk Practitioner]  = sel_prac
)",
    "#,##0");

add("Lapsed (Set Inactive)",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN CALCULATE(
    SUM('_Metric Actuals'[Numerator]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric]           = ""lapsed_deactivated"",
    '_Metric Actuals'[fk Practice Site] = sel_site,
    '_Metric Actuals'[fk Practitioner]  = sel_prac
)",
    "#,##0");

add("Lapsed (Silently)",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN CALCULATE(
    SUM('_Metric Actuals'[Numerator]),
    TREATAS(VALUES('List Date'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric]           = ""lapsed_calculated"",
    '_Metric Actuals'[fk Practice Site] = sel_site,
    '_Metric Actuals'[fk Practitioner]  = sel_prac
)",
    "#,##0");

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

// Recall model (two sources): Dentist/Hygiene Retention Outlook (FORWARD, patient recall dates) and
// Dentist/Hygiene Recall Conversion (REACTIVE, recall-record status). All four are materialised in
// Gold.Fact_Metric_Actuals and read date-blind (currate shape) -- retargeted by TabularEditor_MetricActuals.csx.
add("Dentist Retention Outlook",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR n = CALCULATE( SUM('_Metric Actuals'[Numerator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""dentist_retention_outlook"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
VAR d = CALCULATE( SUM('_Metric Actuals'[Denominator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""dentist_retention_outlook"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
RETURN DIVIDE(n, d)",
    "#,##0.0%");
add("Hygiene Retention Outlook",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR n = CALCULATE( SUM('_Metric Actuals'[Numerator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""hygiene_retention_outlook"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
VAR d = CALCULATE( SUM('_Metric Actuals'[Denominator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""hygiene_retention_outlook"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
RETURN DIVIDE(n, d)",
    "#,##0.0%");
add("Dentist Recall Conversion",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR n = CALCULATE( SUM('_Metric Actuals'[Numerator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""dentist_recall_conversion"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
VAR d = CALCULATE( SUM('_Metric Actuals'[Denominator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""dentist_recall_conversion"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
RETURN DIVIDE(n, d)",
    "#,##0.0%");
add("Hygiene Recall Conversion",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR n = CALCULATE( SUM('_Metric Actuals'[Numerator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""hygiene_recall_conversion"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
VAR d = CALCULATE( SUM('_Metric Actuals'[Denominator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""hygiene_recall_conversion"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )
RETURN DIVIDE(n, d)",
    "#,##0.0%");

// At Risk Patients: distinct active patients with no relevant future appointment across any retention
// route (recall due <=4wk, cancelled not rebooked, open treatment no appt). Reads Gold.Fact_Patient_At_Risk
// (PBI '_Patient At Risk'); slice the report by [Risk Route] / [Risk Detail] for each route or the
// 'No Recall' / falling-through list. Site/practitioner respected via the fact's relationships.
add("At Risk Patients",
    @"DISTINCTCOUNT('_Patient At Risk'[fk Patient])",
    "#,##0");

// Overdue Recalls: recalls that are DUE but the practice has not actioned (open/Unbooked, past due,
// no reminder sent) -- a process/backlog measure of the practice's own reach-out, not patient behaviour.
// Materialised in Fact_Metric_Actuals (date-blind current count); retargeted by MetricActuals.csx.
add("Overdue Recalls",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN CALCULATE( SUM('_Metric Actuals'[Numerator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""overdue_recalls"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = -1 )",
    "#,##0");

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

// Contactability is about the ACTIVE base (inactive patients have contact removed), so both
// numerator and denominator are active-scoped -> % of ACTIVE patients contactable (~94%), not
// diluted by the ~21k historical/inactive patients.
add("Email Details Rate",
    @"DIVIDE(
    CALCULATE(
        SUM('List Patients'[Patient Count]),
        NOT ISBLANK('List Patients'[Email Address]),
        'List Patients'[Active] = TRUE()),
    CALCULATE(
        SUM('List Patients'[Patient Count]),
        'List Patients'[Active] = TRUE()))",
    "#,##0.0%");

add("Phone Details Rate",
    @"DIVIDE(
    CALCULATE(
        SUM('List Patients'[Patient Count]),
        NOT ISBLANK('List Patients'[Mobile Phone])
        || NOT ISBLANK('List Patients'[Home Phone]),
        'List Patients'[Active] = TRUE()),
    CALCULATE(
        SUM('List Patients'[Patient Count]),
        'List Patients'[Active] = TRUE()))",
    "#,##0.0%");

// ── Derived Target / vs-Target / BG per KPI (data-driven) ─────────────────────

kpi("New Patients",             "#,##0",    tDaily("new_patients"),         vPct("New Patients"),               bgHigherEff("New Patients", "new_patients"));
kpi("Net Patient Growth",       "#,##0",    tEffRunRate("net_patient_growth"),   vPctP("Net Patient Growth"),        bgHigherEff("Net Patient Growth", "net_patient_growth"));
kpi("Lapsed Patients",          "#,##0",    tDaily("lapsed_patients"),      vPctGreyP("Lapsed Patients"),       bgLowerEffGrey("Lapsed Patients", "lapsed_patients"));
kpi("Lapsed (Set Inactive)",    "#,##0",    tDaily("lapsed_deactivated"),   vPctGreyP("Lapsed (Set Inactive)"), bgLowerEffGrey("Lapsed (Set Inactive)", "lapsed_deactivated"));
kpi("Lapsed (Silently)",        "#,##0",    tDaily("lapsed_calculated"),    vPctGreyP("Lapsed (Silently)"),     bgLowerEffGrey("Lapsed (Silently)", "lapsed_calculated"));
kpi("Active Patients",          "#,##0",    tEffAdd("active_patients"),             vPctGreyP("Active Patients"),       bgHigherEffGrey("Active Patients", "active_patients"));
kpi("Recall Effectiveness",     "#,##0.0%", tEff100("recall_compliance"),        vPp("Recall Effectiveness"),        bgHigherPp("Recall Effectiveness", "recall_compliance"));
kpi("Patient Retention",        "#,##0.0%", tEff100("patient_retention"),        vPpP("Patient Retention"),          bgHigherPp("Patient Retention", "patient_retention"));
kpi("Recalls Overdue Not Sent", "#,##0.0%", tEff100("recalls_overdue_not_sent"), vPpP("Recalls Overdue Not Sent"),   bgLowerPp("Recalls Overdue Not Sent", "recalls_overdue_not_sent"));
kpi("Dentist Retention Outlook","#,##0.0%", tEff100("dentist_retention_outlook"), vPpGreyP("Dentist Retention Outlook"), bgHigherPpGrey("Dentist Retention Outlook", "dentist_retention_outlook"));
kpi("Hygiene Retention Outlook","#,##0.0%", tEff100("hygiene_retention_outlook"), vPpGreyP("Hygiene Retention Outlook"), bgHigherPpGrey("Hygiene Retention Outlook", "hygiene_retention_outlook"));
kpi("Dentist Recall Conversion","#,##0.0%", tEff100("dentist_recall_conversion"), vPpGreyP("Dentist Recall Conversion"), bgHigherPpGrey("Dentist Recall Conversion", "dentist_recall_conversion"));
kpi("Hygiene Recall Conversion","#,##0.0%", tEff100("hygiene_recall_conversion"), vPpGreyP("Hygiene Recall Conversion"), bgHigherPpGrey("Hygiene Recall Conversion", "hygiene_recall_conversion"));
kpi("Overdue Recalls",          "#,##0",    tEffAdd("overdue_recalls"),             vPctGreyP("Overdue Recalls"),       bgLowerEffGrey("Overdue Recalls", "overdue_recalls"));
kpi("Email Details Rate",       "#,##0.0%", tEff100("email_details_rate"),       vPpP("Email Details Rate"),         bgHigherPp("Email Details Rate", "email_details_rate"));
kpi("Phone Details Rate",       "#,##0.0%", tEff100("phone_details_rate"),       vPpP("Phone Details Rate"),         bgHigherPp("Phone Details Rate", "phone_details_rate"));

Info("Patients KPI measures created (data-driven).");
}

// ===================== Revenue =====================
{
// Revenue KPI measures — data-driven generation.
//
// Each KPI card needs three derived measures: a Target, a "vs Target" variance
// label, and a BG colour. These were ~40 near-identical lines per KPI; they're
// now generated from per-KPI specs via the builder functions below. The DAX is
// functionally identical to the previous hand-written version (DAX ignores
// whitespace). Value measures stay bespoke (each has unique logic).
//
// NOTE: Tabular Editor's C# does NOT support string interpolation (dollar-prefixed
// strings), so templates are verbatim strings with {b}/{key} placeholders filled
// by .Replace().

var t = Model.Tables["_Measures"];
var g = "Revenue KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Target DAX builders (target model: Fact_Daily_Targets + Target_Level resolution + FTE) ──
// lvl: a practitioner in context -> their Custom Role; a role selected -> that role; else Practice.
// The *FTE builders scale the per-FTE role target by SUM(FTE) of the practitioners in context;
// at Practice level the entered whole-practice number is used as-is (fte = 1).
Func<string,string> band = key => (@"CALCULATE(
    MAX('_Daily Targets'[Variance]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)").Replace("{key}", key);

Func<string,string> tCum = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
RETURN IF(ISBLANK(base_t), BLANK(), base_t)").Replace("{key}", key);

Func<string,string> tCumFTE = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR fte = IF(lvl = ""Practice"", 1, SUM('List Practitioners'[FTE]))
RETURN IF(ISBLANK(base_t), BLANK(), base_t * fte)").Replace("{key}", key);

Func<string,string> tRate = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
RETURN CALCULATE(
    MAX('_Daily Targets'[Annual Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)").Replace("{key}", key);

Func<string,string> tRateFTE = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    MAX('_Daily Targets'[Annual Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR fte = IF(lvl = ""Practice"", 1, SUM('List Practitioners'[FTE]))
RETURN IF(ISBLANK(base_t), BLANK(), base_t * fte)").Replace("{key}", key);

Func<string,string> tRate100 = key => tRate(key) + " / 100";

// ── vs-Target DAX builders ───────────────────────────────────────────────────
Func<string,string> vPct = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPctGrey = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(actual) || ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPp = b => (@"VAR actual  = [{b}]
VAR target  = [{b} Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(actual) || ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))").Replace("{b}", b);

// ── BG colour DAX builders (band from _Daily Targets[Variance] at the resolved level) ──
Func<string,string,string> bgHigherRefF = (b, key) => (@"VAR actual = [{b}]
VAR lvl    = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target = [{b} Target]
VAR band   = {band}
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")").Replace("{band}", band(key)).Replace("{b}", b).Replace("{key}", key);

// In the new model target+band both come from the fact, so higher=better Ref and Eff are identical.
Func<string,string,string> bgHigherEffF = bgHigherRefF;

// lower=better; grey=true adds the blank-actual grey row (e.g. Outstanding Invoices)
Func<string,string,bool,string> bgLowerEffF = (b, key, grey) => {
    var greyRow = grey ? @"
    ISBLANK(actual), ""#E0E0E0""," : "";
    return (@"VAR actual = [{b}]
VAR lvl    = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target = [{b} Target]
VAR band   = {band}
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",{grey}
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")").Replace("{band}", band(key)).Replace("{b}", b).Replace("{key}", key).Replace("{grey}", greyRow);
};

Func<string,string,string> bgHigherPpF = (b, key) => (@"VAR actual = [{b}]
VAR lvl     = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target  = [{b} Target]
VAR band    = {band}
VAR diff_pp = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")").Replace("{band}", band(key)).Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerPpF = (b, key) => (@"VAR actual = [{b}]
VAR lvl     = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target  = [{b} Target]
VAR band    = {band}
VAR diff_pp = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp <= -band, ""#1a7f3c"",
    diff_pp <= 0,     ""#6abf7b"",
    diff_pp <= band,  ""#f4a261"",
                      ""#c0392b"")").Replace("{band}", band(key)).Replace("{b}", b).Replace("{key}", key);

// Emits the three derived measures for a KPI from pre-built DAX.
Action<string,string,string,string,string> kpi = (baseName, fmt, targetDax, vsDax, bgDax) => {
    add(baseName + " Target",    targetDax, fmt);
    add(baseName + " vs Target", vsDax,     "");
    add(baseName + " BG",        bgDax,     "");
};

// ── Value measures (bespoke) ─────────────────────────────────────────────────

add("Total Revenue",
    @"SUM('_Invoice Items'[Total Price])",
    "£#,##0");

add("NHS Revenue",
    @"CALCULATE(
    SUM('_Invoice Items'[Total Price]),
    '_Invoice Items'[NHS Charge] > 0)",
    "£#,##0");

add("Private Revenue",
    @"CALCULATE(
    SUM('_Invoice Items'[Total Price]),
    '_Invoice Items'[NHS Charge] = 0)",
    "£#,##0");

add("Outstanding Invoices",
    @"VAR snap_fk =
    MAXX(
        FILTER( ALLSELECTED( '_KPI Snapshot' ), '_KPI Snapshot'[Snapshot Grain] = ""weekly"" ),
        '_KPI Snapshot'[fk Date]
    )
RETURN
CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[fk Date]        = snap_fk,
    '_KPI Snapshot'[Metric]         = ""outstanding_invoices"",
    '_KPI Snapshot'[Snapshot Grain] = ""weekly""
)",
    "£#,##0");

add("Revenue Per Patient",
    @"DIVIDE([Total Revenue], [Active Patients])",
    "£#,##0");

add("Revenue Per Clinical Hour",
    @"VAR by_prac_day =
SUMMARIZE(
    FILTER(
        'Aggregate Site Patient Practitioner Daily',
        RELATED('List Practitioners'[Role]) IN {""dentist"",""hygienist"",""orthodontist"",""specialist"",""therapist""}
    ),
    'Aggregate Site Patient Practitioner Daily'[fk Practitioner],
    'Aggregate Site Patient Practitioner Daily'[fk Date],
    ""WH"", MAX('Aggregate Site Patient Practitioner Daily'[Worked Hours]))
VAR total_worked = SUMX(by_prac_day, [WH])
RETURN DIVIDE([Total Revenue], total_worked)",
    "£#,##0");

add("DNA Revenue Lost",
    @"VAR dna_count =
    CALCULATE(
        SUM('Aggregate Site Patient Practitioner Daily'[DNA Appointments]),
        REMOVEFILTERS('List Practitioners')
    )
VAR avg_appt_value =
    DIVIDE(
        CALCULATE([Total Revenue],
            REMOVEFILTERS('List Date'),
            REMOVEFILTERS('List Practitioners')),
        CALCULATE(
            SUM('Aggregate Site Patient Practitioner Daily'[Appointments]),
            REMOVEFILTERS('List Date'),
            REMOVEFILTERS('List Practitioners'))
    )
RETURN dna_count * avg_appt_value",
    "£#,##0");

add("Deposit Value",
    @"DIVIDE(SUM('_Payments'[Deposit Amount]), [Total Revenue])",
    "0.0%");

// Invoice grain split: per-invoice discount (header Amount - sum of its line Total Price,
// when positive) is precomputed as Fact_Invoices.Discount_Amount, so this is a simple ratio.
add("Discounts",
    @"DIVIDE(SUM('_Invoices'[Discount Amount]), [Total Revenue])",
    "0.0%");

// ── Derived Target / vs-Target / BG per KPI (data-driven) ─────────────────────

kpi("Total Revenue",             "£#,##0", tCumFTE("total_revenue"),            vPct("Total Revenue"),             bgHigherRefF("Total Revenue", "total_revenue"));
kpi("NHS Revenue",               "£#,##0", tCumFTE("nhs_revenue"),              vPct("NHS Revenue"),               bgHigherRefF("NHS Revenue", "nhs_revenue"));
kpi("Private Revenue",           "£#,##0", tCumFTE("private_revenue"),          vPct("Private Revenue"),           bgHigherRefF("Private Revenue", "private_revenue"));
kpi("Outstanding Invoices",      "£#,##0", tRate("outstanding_invoices"),    vPctGrey("Outstanding Invoices"),  bgLowerEffF("Outstanding Invoices", "outstanding_invoices", true));
kpi("Revenue Per Patient",       "£#,##0", tRate("revenue_per_patient"),        vPct("Revenue Per Patient"),       bgHigherEffF("Revenue Per Patient", "revenue_per_patient"));
kpi("Revenue Per Clinical Hour", "£#,##0", tRate("revenue_per_clinical_hour"),  vPct("Revenue Per Clinical Hour"), bgHigherEffF("Revenue Per Clinical Hour", "revenue_per_clinical_hour"));
kpi("DNA Revenue Lost",          "£#,##0", tRate("dna_revenue_lost"),           vPct("DNA Revenue Lost"),          bgLowerEffF("DNA Revenue Lost", "dna_revenue_lost", false));
kpi("Deposit Value",             "0.0%",   tRate100("deposit_ratio"),           vPp("Deposit Value"),              bgHigherPpF("Deposit Value", "deposit_ratio"));
kpi("Discounts",                 "0.0%",   tRate100("discounts"),               vPp("Discounts"),                  bgLowerPpF("Discounts", "discounts"));

Info("Revenue KPI measures created (data-driven).");
}

// ===================== Scheduling =====================
{
// Scheduling KPI measures — data-driven generation.
//
// Per-KPI Target / vs-Target / BG blocks are generated from per-KPI specs via the
// builder functions below. DAX is functionally identical to the previous
// hand-written version (DAX ignores whitespace). Value measures stay bespoke.
// All targets come from '_Daily Targets' (Fact_Daily_Targets), resolved by Target_Level.
//
// NOTE: Tabular Editor's C# has no string interpolation (dollar-prefixed strings),
// so templates are verbatim @"..." with {b}/{key} placeholders filled via .Replace().
//
// Builder variants used on this page (Scheduling has no practitioner-prefix and no
// No-data/grey cards, so only the plain variants are defined):
//   Target : tEff (plain, count) | tEff100 (ratios, /100)
//   vs     : vPct (relative %) | vPp (absolute pp)
//   BG     : bgHigherPp | bgLowerPp (pp bands) | bgLowerEff (relative-% band, lower-is-better)

var t = Model.Tables["_Measures"];
var g = "Scheduling KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Target builders (target model: Fact_Daily_Targets, Target_Level resolution + FTE) ──
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

Func<string,string> vPp = b => (@"VAR actual  = [{b}]
VAR target  = [{b} Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))").Replace("{b}", b);

// ── BG builders (target from [b Target]; band from _Daily Targets[Variance] at the resolved level) ─────────────────────────
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

Func<string,string,string> bgLowerPp = (b, key) => (@"VAR actual   = [{b}]
VAR lvl      = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Daily Targets'[Variance]), TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]), '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp <= -band, ""#1a7f3c"",
    diff_pp <= 0,     ""#6abf7b"",
    diff_pp <= band,  ""#f4a261"",
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

Action<string,string,string,string,string> kpi = (baseName, fmt, targetDax, vsDax, bgDax) => {
    add(baseName + " Target",    targetDax, fmt);
    add(baseName + " vs Target", vsDax,     "");
    add(baseName + " BG",        bgDax,     "");
};

// ── Value measures (bespoke) ─────────────────────────────────────────────────

// Diary Fill: SCHEDULED appointment hours / worked hours -- how full the diary is.
// Worked Hours is stored per practitioner-day; deduplicate to avoid inflating it when a
// practitioner sees multiple patients on the same day. (Retargeted onto _Metric Actuals
// [diary_fill] by TabularEditor_MetricActuals.csx; bespoke fallback kept for standalone runs.)
add("Diary Fill",
    @"VAR by_prac_day =
    SUMMARIZE(
        'Aggregate Site Patient Practitioner Daily',
        'Aggregate Site Patient Practitioner Daily'[fk Practitioner],
        'Aggregate Site Patient Practitioner Daily'[fk Date],
        ""WH"", MAX('Aggregate Site Patient Practitioner Daily'[Worked Hours]))
VAR total_worked = SUMX(by_prac_day, [WH])
RETURN
    DIVIDE(
        SUM('Aggregate Site Patient Practitioner Daily'[Appointment Hours]),
        total_worked)",
    "#,##0.0%");

// Chair Utilisation: ACTUAL capped in-chair hours / worked hours -- real time in the chair.
// (Retargeted onto _Metric Actuals[chair_utilisation]; bespoke fallback for standalone runs.)
add("Chair Utilisation",
    @"VAR by_prac_day =
    SUMMARIZE(
        'Aggregate Site Patient Practitioner Daily',
        'Aggregate Site Patient Practitioner Daily'[fk Practitioner],
        'Aggregate Site Patient Practitioner Daily'[fk Date],
        ""WH"", MAX('Aggregate Site Patient Practitioner Daily'[Worked Hours]))
VAR total_worked = SUMX(by_prac_day, [WH])
RETURN
    DIVIDE(
        SUM('Aggregate Site Patient Practitioner Daily'[Chair Hours]),
        total_worked)",
    "#,##0.0%");

// Patient Tracked in Surgery: appts with an in-surgery timestamp / all appts (reception tracking).
add("Patient Tracked in Surgery",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[Tracked Appointments]),
    SUM('Aggregate Site Patient Practitioner Daily'[Appointments]))",
    "#,##0.0%");

add("DNA Rate",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[DNA Appointments]),
    SUM('Aggregate Site Patient Practitioner Daily'[Appointments]))",
    "#,##0.0%");

// Days until next available slot — MIN across practitioners
add("Days Until Next 30 Minute Free",
    @"MIN('Aggregate Site Practitioner Current'[Days Until Next 30 Mins])",
    "#,##0");

add("Book Before You Leave",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[BBYL Appointments]),
    SUM('Aggregate Site Patient Practitioner Daily'[Appointments]))",
    "#,##0.0%");

// Home Detail measures: Cancellation Frequency and Short Notice Cancellation Rate
// read from the Aggregate table (Cancelled_Appointments / Short_Notice_Cancellations
// columns) to avoid cross-table relationship dependency on _Appointments[Is Cancelled].

add("Cancellation Frequency",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[Cancelled Appointments]),
    SUM('Aggregate Site Patient Practitioner Daily'[Appointments]))",
    "0.0%");

add("Short Notice Cancellation Rate",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[Short Notice Cancellations]),
    SUM('Aggregate Site Patient Practitioner Daily'[Cancelled Appointments]))",
    "#,##0.0%");

// ── Forward heatmap: Diary Fill projected forwards ───────────────────────────
// Same metric as [Diary Fill], but its date axis comes from 'List Date Unconstrained'
// (a second alias of PBI.[List Date]) so the external period filter can't clamp it to today.
// Put 'List Date Unconstrained' on the heatmap axis + a relative-date slicer (e.g. 0..13 days)
// to look as far forward as you like. REMOVEFILTERS drops the app's period filter; the TREATAS
// on 'List Date Unconstrained'[pk Date] re-applies the heatmap's date window onto the fact --
// robust whether or not the physical relationship you add to _Metric Actuals is active.
// (Works forwards because 7,040 future appts + 5,127 future rota rows exist in the aggregate.)
add("Diary Fill (Forward)",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR n = CALCULATE( SUM('_Metric Actuals'[Numerator]),
    REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Date Unconstrained'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""diary_fill"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )
VAR d = CALCULATE( SUM('_Metric Actuals'[Denominator]),
    REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Date Unconstrained'[pk Date]), '_Metric Actuals'[fk Date]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""diary_fill"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )
RETURN DIVIDE(n, d)",
    "#,##0.0%");

// Forward Book Value — the £ companion to the % fill (confirmed forward revenue, next 7 days).
// Display measure (no target triple; add a catalog row later if you want a £ target).
add("Forward Book Value",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
RETURN CALCULATE( SUM('_Metric Actuals'[Numerator]), REMOVEFILTERS('List Date'), REMOVEFILTERS('List Date Grouping'),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Metric Actuals'[Tenant ID]),
    '_Metric Actuals'[Metric] = ""forward_book_value"", '_Metric Actuals'[fk Practice Site] = sel_site, '_Metric Actuals'[fk Practitioner] = sel_prac )",
    "£#,##0");

// ── Derived Target / vs-Target / BG per KPI (data-driven) ─────────────────────
// chair_utilisation     → above + percent → absolute pp
// dna_rate              → below + percent → absolute pp (lower is better)
// days_until_30min_free → below + count   → relative %  (lower is better)
// days_until_1hr_free   → below + count   → relative %  (lower is better)
// book_before_you_leave → above + percent → absolute pp
// cancellation_frequency / short_notice → below + percent → absolute pp (lower is better)

kpi("Diary Fill",                       "#,##0.0%", tEff100("diary_fill"),                     vPp("Diary Fill"),                       bgHigherPp("Diary Fill", "diary_fill"));
kpi("Chair Utilisation",                "#,##0.0%", tEff100("chair_utilisation"),              vPp("Chair Utilisation"),                bgHigherPp("Chair Utilisation", "chair_utilisation"));
kpi("Patient Tracked in Surgery",       "#,##0.0%", tEff100("patient_tracked_in_surgery"),     vPp("Patient Tracked in Surgery"),       bgHigherPp("Patient Tracked in Surgery", "patient_tracked_in_surgery"));
kpi("DNA Rate",                         "#,##0.0%", tEff100("dna_rate"),                       vPp("DNA Rate"),                         bgLowerPp("DNA Rate", "dna_rate"));
kpi("Days Until Next 30 Minute Free",   "#,##0",    tEffAdd("days_until_30min_free"),             vPct("Days Until Next 30 Minute Free"),  bgLowerEff("Days Until Next 30 Minute Free", "days_until_30min_free"));
kpi("Book Before You Leave",            "#,##0.0%", tEff100("book_before_you_leave"),          vPp("Book Before You Leave"),            bgHigherPp("Book Before You Leave", "book_before_you_leave"));
kpi("Cancellation Frequency",           "0.0%",     tEff100("cancellation_frequency"),         vPp("Cancellation Frequency"),           bgLowerPp("Cancellation Frequency", "cancellation_frequency"));
kpi("Short Notice Cancellation Rate",   "#,##0.0%", tEff100("short_notice_cancellation_rate"), vPp("Short Notice Cancellation Rate"),   bgLowerPp("Short Notice Cancellation Rate", "short_notice_cancellation_rate"));
// Diary Fill (Forward) is a bespoke heatmap measure (its own unconstrained date axis), so it has
// no data-driven KPI triple here -- colour the heatmap by value, or vs the [Diary Fill Target].

Info("Scheduling KPI measures created (data-driven).");
}

// ===================== Shared =====================
{
var t = Model.Tables["_Measures"];
var g = "_Period Helpers";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── _FY Period Key ────────────────────────────────────────────────────────────
// Returns the FY key without "(YTD)" suffix, e.g. "FY 2026/27".
// Returns "" when no FY filter is active (all-time, Last 12 Months, etc.).

add("_FY Period Key",
    @"VAR raw = SELECTEDVALUE('List Date Grouping'[Date Grouping], """")
RETURN IF(LEFT(raw, 2) = ""FY"", SUBSTITUTE(raw, "" (YTD)"", """"), """")",
    "");

// ── _Period Run Rate ──────────────────────────────────────────────────────────
// Returns the fraction of the financial year's working days that have elapsed.
// = 1.0 when no YTD filter is active (full-year or all-time view).
// Used to prorate annual targets against actual YTD working days.

add("_Period Run Rate",
    @"VAR period_key = [_FY Period Key]
VAR raw        = SELECTEDVALUE('List Date Grouping'[Date Grouping], """")
VAR is_ytd     = CONTAINSSTRING(raw, ""(YTD)"")
VAR fy_working = CALCULATE(
    COUNTROWS('List Date'),
    'List Date'[Financial Year Name] = period_key,
    'List Date'[Is Weekend] = FALSE(),
    'List Date'[Is England Wales Bank Holiday] = FALSE(),
    ALL('List Date'))
VAR elapsed = CALCULATE(
    COUNTROWS('List Date'),
    'List Date'[Financial Year Name] = period_key,
    'List Date'[Full Date] <= TODAY(),
    'List Date'[Is Weekend] = FALSE(),
    'List Date'[Is England Wales Bank Holiday] = FALSE(),
    ALL('List Date'))
RETURN IF(is_ytd && fy_working > 0, DIVIDE(elapsed, fy_working), 1.0)",
    "");

// ── _Is Practitioner Filtered ─────────────────────────────────────────────────
// Returns 1 when the practitioner slicer has a selection, 0 otherwise.
// Used to show ⚠ in variance text for Supports_Practitioner = 0 metrics.

add("_Is Practitioner Filtered",
    @"IF(ISFILTERED('List Practitioners'[pk Practitioner]), 1, 0)",
    "");

// ── _Target FY Key ────────────────────────────────────────────────────────────
// Returns the FY key to use for target lookups.
// When an FY grouping is selected: returns that key, e.g. "FY 2025-26".
// When a non-FY grouping is selected (Last 12M, Last 3M): falls back to the
// current financial year so cards always show a relevant target.

add("_Target FY Key",
    @"VAR selected = [_FY Period Key]
VAR fy_year  = IF(MONTH(TODAY()) >= 4, YEAR(TODAY()), YEAR(TODAY()) - 1)
VAR cur_fy   = ""FY "" & fy_year & ""-"" & RIGHT("""" & (fy_year + 1), 2)
RETURN IF(selected <> """", selected, cur_fy)",
    "");

Info("Period helper measures created. Run this script once before any tab script.");
}

// ===================== SpiderRevenue =====================
{
// TabularEditor_SpiderRevenue.csx
// Creates 21 measures for the Revenue Spider (Deneb radar) visual.
//
// Architecture: ALL individual measures return a RATIO (0–2 range), not raw £.
//   Target sentinel = 1 for every axis.
//   Vega normalises: norm = min(val / 1, 2) / 2  → val=1 → target ring; val=1.2 → 20% above.
//
// Cumulative £ axes (Total Revenue, Private Revenue, NHS Revenue, Outstanding Inv):
//   [X Target] from _Daily Targets is practice-wide.
//   Divide by n_prac to get per-practitioner share; individual = actual / share.
//   AVERAGEX of the ratio = practice_actual / practice_target — meaningful for avg web.
//   Fallback when no target: individual = actual / practice_average (vs average).
//
// Rate/point-in-time axes (Plan Value, Discounts, Deposit Value):
//   Target from _Effective Targets is site-level — same threshold for all practitioners.
//   Fallback when no target: individual = actual / practice_average.
//   Plan Value routes via _Treatment Plan Items[fk_Practitioner] → plan value on List Treatment Plans.
//   (List Treatment Plans[Practitioner_ID] is a raw int with no PBI relationship.)
//
// Lower-is-better inversion (Outstanding Inv, Discounts):
//   Individual = target / actual  → above target ring = below threshold (good).
//   actual = 0 → perfect → return 2 (capped max).  BLANK → no data → return 1 (neutral).
//
// History:
//   *01  21/05/2026  AIH  Initial
//   *02  21/05/2026  AIH  AVERAGEX + avg-fallback for axes without _Targets entries
//   *03  21/05/2026  AIH  Ratio architecture: all individual = ratio vs per-prac target
//   *04  08/06/2026  AIH  Real DAX for Discounts and Deposit Value (was hardcoded 1)
//   *05  09/06/2026  AIH  Fix: compute actual via TREATAS so Deneb row context correctly
//                         isolates per-practitioner figures from _Invoice Items / _Payments
//   *06  09/06/2026  AIH  Fix: Plan Value denominator → practice average (not target) for
//                         meaningful per-practitioner variance; Outstanding Invoices axis
//                         replaced with per-practitioner _Invoice Items[Invoice Amount
//                         Outstanding] as snapshot-based measure cannot split by practitioner
//   *07  09/06/2026  AIH  Fix: tenant scope was using VALUES('List Practice Sites'[Tenant ID])
//                         which has no RLS filter; changed to VALUES('List Practitioners'[Tenant ID])
//                         so tenant capture respects the RLS filter on List Practitioners

var folder = "Spider Revenue";
var table  = "_Measures";

Action<string,string,string> add = (name, dax, fmt) => {
    var m = Model.Tables[table].AddMeasure(name, dax);
    m.DisplayFolder = folder;
    m.FormatString  = fmt;
    m.IsHidden      = false;
};

foreach (var existing in Model.Tables[table].Measures
    .Where(m => m.DisplayFolder == folder).ToList())
    existing.Delete();

// ── Individual — all return a ratio ──────────────────────────────────────────

add("Spider Rev Total Revenue",
    @"VAR prac_pks    = VALUES('List Practitioners'[pk Practitioner])
VAR actual      = CALCULATE(SUM('_Invoice Items'[Total Price]), TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR practice_tgt = [Total Revenue Target]
VAR n           = CALCULATE(COUNTROWS('List Practitioners'), FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])))
VAR share       = DIVIDE(practice_tgt, n)
VAR fallback    = AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [Total Revenue])
RETURN IFERROR(DIVIDE(actual, IF(share > 0, share, fallback)), 0)",
    @"0.00");

add("Spider Rev Private Revenue",
    @"VAR prac_pks    = VALUES('List Practitioners'[pk Practitioner])
VAR actual      = CALCULATE(SUM('_Invoice Items'[Total Price]), '_Invoice Items'[NHS Charge] = 0, TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR practice_tgt = [Private Revenue Target]
VAR n           = CALCULATE(COUNTROWS('List Practitioners'), FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])))
VAR share       = DIVIDE(practice_tgt, n)
VAR fallback    = AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [Private Revenue])
RETURN IFERROR(DIVIDE(actual, IF(share > 0, share, fallback)), 0)",
    @"0.00");

add("Spider Rev NHS Revenue",
    @"VAR prac_pks    = VALUES('List Practitioners'[pk Practitioner])
VAR actual      = CALCULATE(SUM('_Invoice Items'[Total Price]), '_Invoice Items'[NHS Charge] > 0, TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR practice_tgt = [NHS Revenue Target]
VAR n           = CALCULATE(COUNTROWS('List Practitioners'), FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])))
VAR share       = DIVIDE(practice_tgt, n)
VAR fallback    = AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [NHS Revenue])
RETURN IFERROR(DIVIDE(actual, IF(share > 0, share, fallback)), 0)",
    @"0.00");

// Lower-is-better: per-prac threshold / actual → >1 means below threshold (good)
// Uses _Invoices[Invoice Amount Outstanding] attributed to the invoice's representative
// clinician (Fact_Invoices.fk_Practitioner) -- invoice grain, no line-fold double count.
add("Spider Rev Outstanding Invoices",
    @"VAR prac_pks    = VALUES('List Practitioners'[pk Practitioner])
VAR actual      = COALESCE(
    CALCULATE(SUM('_Invoices'[Invoice Amount Outstanding]), TREATAS(prac_pks, '_Invoices'[fk Practitioner])),
    0)
VAR practice_tgt = [Outstanding Invoices Target]
VAR n           = CALCULATE(COUNTROWS('List Practitioners'), FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])))
VAR share       = DIVIDE(practice_tgt, n)
VAR fallback    = AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])),
    CALCULATE(SUM('_Invoices'[Invoice Amount Outstanding]), TREATAS(VALUES('List Practitioners'[pk Practitioner]), '_Invoices'[fk Practitioner])))
RETURN IF(ISBLANK(practice_tgt),
    IF(actual = 0, 2, IFERROR(DIVIDE(fallback, actual), 1)),
    IF(actual = 0, 2, IFERROR(DIVIDE(share, actual), 2)))",
    @"0.00");

// Rate: this practitioner's average plan value vs the practice-wide average.
// Delegates to [Average Plan Value] for the individual value (known-good TREATAS pattern).
// practice_avg uses ALL on all three related tables to break the residual filter chain
// that [FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID]))] alone leaves in place on _Treatment Plan Items and
// List Treatment Plans — without this, every AVERAGEX iteration sees only the selected
// practitioner's plans and practice_avg collapses to actual, giving ratio = 1.0 always.
add("Spider Rev Plan Value",
    @"VAR actual       = [Average Plan Value]
VAR practice_avg = CALCULATE(
    [Average Plan Value],
    FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])),
    ALLSELECTED('_Treatment Plan Items'),
    ALLSELECTED('List Treatment Plans')
)
RETURN IFERROR(DIVIDE(actual, IF(practice_avg > 0, practice_avg, 1)), 0)",
    @"0.00");

// Lower-is-better: target_rate / actual_rate → above target ring = fewer discounts (good)
// actual = 0 → no discounts at all → perfect score (2); BLANK → no invoice data → neutral (1)
add("Spider Rev Discounts",
    @"VAR prac_pks  = VALUES('List Practitioners'[pk Practitioner])
VAR prac_rev  = CALCULATE(SUM('_Invoice Items'[Total Price]), TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR prac_disc = CALCULATE(SUM('_Invoices'[Discount Amount]), TREATAS(prac_pks, '_Invoices'[fk Practitioner]))
VAR actual    = DIVIDE(prac_disc, prac_rev)
VAR tgt       = [Discounts Target]
VAR fallback  = AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [Discounts])
VAR denom     = IF(NOT ISBLANK(tgt), tgt, fallback)
RETURN IF(
    ISBLANK(actual), 1,
    IF(actual = 0,   2,
    IFERROR(DIVIDE(denom, actual), 1)))",
    @"0.00");

// Higher-is-better: actual_rate / target_rate → above target ring = higher deposit coverage (good)
// BLANK actual → no payment data → neutral (0 rendered as centre)
add("Spider Rev Deposit Value",
    @"VAR prac_pks = VALUES('List Practitioners'[pk Practitioner])
VAR prac_dep  = CALCULATE(SUM('_Payments'[Deposit Amount]), TREATAS(prac_pks, '_Payments'[fk Practitioner]))
VAR prac_rev  = CALCULATE(SUM('_Invoice Items'[Total Price]), TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR actual    = DIVIDE(prac_dep, prac_rev)
VAR tgt       = [Deposit Value Target]
VAR fallback  = AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [Deposit Value])
VAR denom     = IF(NOT ISBLANK(tgt), tgt, IF(fallback > 0, fallback, 1))
RETURN IFERROR(DIVIDE(actual, denom), 0)",
    @"0.00");

// ── Targets — sentinel 1 on ratio scale ──────────────────────────────────────

add("Spider Rev Tgt Total Revenue",       @"1", @"0.00");
add("Spider Rev Tgt Private Revenue",     @"1", @"0.00");
add("Spider Rev Tgt NHS Revenue",         @"1", @"0.00");
add("Spider Rev Tgt Outstanding Invoices",@"1", @"0.00");
add("Spider Rev Tgt Plan Value",          @"1", @"0.00");
add("Spider Rev Tgt Discounts",           @"1", @"0.00");
add("Spider Rev Tgt Deposit Value",       @"1", @"0.00");

// ── Practice averages — AVERAGEX of ratio gives practice_actual/practice_target ─

add("Spider Rev Avg Total Revenue",
    @"AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [Spider Rev Total Revenue])",
    @"0.00");

add("Spider Rev Avg Private Revenue",
    @"AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [Spider Rev Private Revenue])",
    @"0.00");

add("Spider Rev Avg NHS Revenue",
    @"AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [Spider Rev NHS Revenue])",
    @"0.00");

add("Spider Rev Avg Outstanding Invoices",
    @"AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [Spider Rev Outstanding Invoices])",
    @"0.00");

add("Spider Rev Avg Plan Value",
    @"VAR pa = CALCULATE([Average Plan Value], FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), ALLSELECTED('_Treatment Plan Items'), ALLSELECTED('List Treatment Plans'))
RETURN IF(pa > 0, 1, BLANK())",
    @"0.00");

add("Spider Rev Avg Discounts",
    @"AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [Spider Rev Discounts])",
    @"0.00");

add("Spider Rev Avg Deposit Value",
    @"AVERAGEX(FILTER(ALL('List Practitioners'), 'List Practitioners'[Tenant ID] IN VALUES('List Practitioners'[Tenant ID])), [Spider Rev Deposit Value])",
    @"0.00");
}
