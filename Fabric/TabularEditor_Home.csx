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
//   Revenue Per Hour / Revenue Per Hour vs Target / ...BG        (Revenue KPIs)
//   Chair Utilisation / Chair Utilisation vs Target / ...BG      (Scheduling KPIs)
//   DNA Rate / DNA Rate vs Target / DNA Rate BG                  (Scheduling KPIs)
//   New Patients / New Patients vs Target / New Patients BG      (Patients KPIs)
//
// This folder adds only the two new Tier 1 measures not defined elsewhere:
//   Forward Book Value  — confirmed appointment pipeline (next 30 days, £)
//   DNA Revenue Lost    — estimated revenue lost to DNAs in the period (£)

// ── Value measures ───────────────────────────────────────────────────────────

// Forward Book Value: count of booked appointments in the next 30 days
// multiplied by the all-time average revenue per appointment.
// Date filter is removed so future appointments (outside selected period)
// are always included; site/practitioner filters are preserved.
add("Forward Book Value",
    @"VAR future_booked =
    CALCULATE(
        COUNTROWS('_Appointments'),
        REMOVEFILTERS('_Date'),
        '_Appointments'[Start Time] > NOW(),
        '_Appointments'[Start Time] <= NOW() + 30,
        '_Appointments'[Is Cancelled] = FALSE(),
        '_Appointments'[Is DNA] = FALSE()
    )
VAR avg_appt_value =
    DIVIDE(
        CALCULATE([Total Revenue],    REMOVEFILTERS('_Date')),
        CALCULATE(SUM('Aggregate Site Patient Practitioner Daily'[Appointments]), REMOVEFILTERS('_Date'))
    )
RETURN future_booked * avg_appt_value",
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
        CALCULATE([Total Revenue],    REMOVEFILTERS('_Date')),
        CALCULATE(SUM('Aggregate Site Patient Practitioner Daily'[Appointments]), REMOVEFILTERS('_Date'))
    )
RETURN dna_count * avg_appt_value",
    "£#,##0");

// ── Target measures ──────────────────────────────────────────────────────────
// Forward Book Value: point-in-time target (no annualisation — it's always
// the next 30 days regardless of the selected period).
add("Forward Book Value Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""forward_book_value""),
    '_Targets'[Target Value])",
    "£#,##0");

// DNA Revenue Lost: maximum acceptable £ lost per period.
add("DNA Revenue Lost Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost""),
    '_Targets'[Target Value])",
    "£#,##0");

// ── Variance measures ────────────────────────────────────────────────────────
add("Forward Book Value vs Target",
    @"VAR actual = [Forward Book Value]
VAR target = [Forward Book Value Target]
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
// forward_book_value  → above is good → relative %
// dna_revenue_lost    → below is good → relative %, sign inverted

add("Forward Book Value BG",
    @"VAR actual = [Forward Book Value]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""forward_book_value""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""forward_book_value""), '_Targets'[Variance])
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
