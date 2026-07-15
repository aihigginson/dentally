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
