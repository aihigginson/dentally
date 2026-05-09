var t = Model.Tables["_Measures"];
var g = "Scheduling KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Value measures ───────────────────────────────────────────────────────────

// Chair utilisation: appointment hours / worked hours
// Worked Hours is stored per practitioner-day; deduplicate to avoid
// inflating it when a practitioner sees multiple patients on the same day
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
        SUM('Aggregate Site Patient Practitioner Daily'[Appointment Hours]),
        total_worked)",
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

add("Days Until Next 1 Hour Free",
    @"MIN('Aggregate Site Practitioner Current'[Days Until Next 1 Hour Free])",
    "#,##0");

add("Book Before You Leave",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[BBYL Appointments]),
    SUM('Aggregate Site Patient Practitioner Daily'[Appointments]))",
    "#,##0.0%");

// ── BG colour measures ───────────────────────────────────────────────────────
// chair_utilisation     → above + percent → absolute pp
// dna_rate              → below + percent → absolute pp (lower is better)
// days_until_30min_free → below + count   → relative %  (lower is better)
// days_until_1hr_free   → below + count   → relative %  (lower is better)
// book_before_you_leave → above + percent → absolute pp

add("Chair Utilisation BG",
    @"VAR actual   = [Chair Utilisation]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""chair_utilisation""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""chair_utilisation""), '_Targets'[Variance])
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp >= band,   ""#1a7f3c"",
    diff_pp >= 0,          ""#6abf7b"",
    diff_pp >= -band,  ""#f4a261"",
                           ""#c0392b"")",
    "");

add("DNA Rate BG",
    @"VAR actual   = [DNA Rate]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_rate""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_rate""), '_Targets'[Variance])
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp <= -band,  ""#1a7f3c"",
    diff_pp <= 0,          ""#6abf7b"",
    diff_pp <= band,   ""#f4a261"",
                           ""#c0392b"")",
    "");

add("Days Until Next 30 Minute Free BG",
    @"VAR actual   = [Days Until Next 30 Minute Free]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""days_until_30min_free""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""days_until_30min_free""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct <= -band,  ""#1a7f3c"",
    pct <= 0,          ""#6abf7b"",
    pct <= band,   ""#f4a261"",
                       ""#c0392b"")",
    "");

add("Days Until Next 1 Hour Free BG",
    @"VAR actual   = [Days Until Next 1 Hour Free]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""days_until_1hr_free""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""days_until_1hr_free""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct <= -band,  ""#1a7f3c"",
    pct <= 0,          ""#6abf7b"",
    pct <= band,   ""#f4a261"",
                       ""#c0392b"")",
    "");

add("Book Before You Leave BG",
    @"VAR actual   = [Book Before You Leave]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""book_before_you_leave""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""book_before_you_leave""), '_Targets'[Variance])
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp >= band,   ""#1a7f3c"",
    diff_pp >= 0,          ""#6abf7b"",
    diff_pp >= -band,  ""#f4a261"",
                           ""#c0392b"")",
    "");

Info("Scheduling KPI measures created.");
