var t = Model.Tables["_Measures"];
var g = "Home KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Page 1 (Tier 1 overview) ─────────────────────────────────────────────────
// The following existing measures are used directly on the Home report page 1
// KPI cards — no new measures needed for them:
//
//   Total Revenue / Total Revenue vs Target / Total Revenue BG   (Revenue KPIs)
//   Revenue Per Clinical Hour / Revenue Per Clinical Hour vs Target / ...BG  (Revenue KPIs)
//   Chair Utilisation / Chair Utilisation vs Target / ...BG      (Scheduling KPIs)
//   DNA Rate / DNA Rate vs Target / DNA Rate BG                  (Scheduling KPIs)
//   Net Patient Growth / Net Patient Growth vs Target / Net Patient Growth BG  (Patients KPIs)
//
// This folder adds only the two new Tier 1 measures not defined elsewhere:
//   Open Courses Value — £ value of open treatment plan items (no approximation)
//   DNA Revenue Lost         — estimated revenue lost to DNAs in the period (£)

// ── Value measures ───────────────────────────────────────────────────────────

// Open Courses Value: most recent weekly snapshot from Fact_KPI_Snapshot.
// Semi-additive: picks the latest fk Date in the slicer selection so the card
// always shows one value. Grain fixed to "weekly" for the Home card.
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

// DNA Revenue Lost: DNA appointments in the selected period multiplied by
// the all-time average revenue per appointment.
// Uses the all-time average as the rate — more stable than period average
// which fluctuates when periods are short.
add("DNA Revenue Lost",
    @"VAR dna_count =
    SUM('Aggregate Site Patient Practitioner Daily'[DNA Appointments])
VAR avg_appt_value =
    DIVIDE(
        CALCULATE([Total Revenue],    REMOVEFILTERS('List Date')),
        CALCULATE(SUM('Aggregate Site Patient Practitioner Daily'[Appointments]), REMOVEFILTERS('List Date'))
    )
RETURN dna_count * avg_appt_value",
    "£#,##0");

// ── Target measures ──────────────────────────────────────────────────────────
// Open Courses Value: point-in-time threshold — minimum acceptable
// open pipeline the practice should hold at any given time.
add("Open Courses Value Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""open_courses_value""),
    '_Targets'[Target Value])",
    "£#,##0");

// DNA Revenue Lost: maximum acceptable £ lost per period.
add("DNA Revenue Lost Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost""),
    '_Targets'[Target Value])",
    "£#,##0");

// ── Variance measures ────────────────────────────────────────────────────────
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

// DNA Revenue Lost: lower is better — sign inverted so ▲ means less than target
add("DNA Revenue Lost vs Target",
    @"VAR actual = [DNA Revenue Lost]
VAR target = [DNA Revenue Lost Target]
VAR pct    = DIVIDE(target - actual, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

// ── BG colour measures ───────────────────────────────────────────────────────
// open_courses_value → above is good → relative %
// dna_revenue_lost         → below is good → relative %, sign inverted

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

add("DNA Revenue Lost BG",
    @"VAR actual = [DNA Revenue Lost]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")",
    "");

Info("Home KPI measures created.");
