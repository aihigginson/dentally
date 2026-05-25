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

// ── Target and variance measures ─────────────────────────────────────────────

add("Chair Utilisation Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""chair_utilisation""),
    '_Targets'[Target Value]) / 100",
    "#,##0.0%");

add("Chair Utilisation vs Target",
    @"VAR actual  = [Chair Utilisation]
VAR target  = [Chair Utilisation Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("DNA Rate Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""dna_rate""),
    '_Targets'[Target Value]) / 100",
    "#,##0.0%");

add("DNA Rate vs Target",
    @"VAR actual  = [DNA Rate]
VAR target  = [DNA Rate Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("Days Until Next 30 Minute Free Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""days_until_30min_free""),
    '_Targets'[Target Value])",
    "#,##0");

add("Days Until Next 30 Minute Free vs Target",
    @"VAR actual = [Days Until Next 30 Minute Free]
VAR target = [Days Until Next 30 Minute Free Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Days Until Next 1 Hour Free Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""days_until_1hr_free""),
    '_Targets'[Target Value])",
    "#,##0");

add("Days Until Next 1 Hour Free vs Target",
    @"VAR actual = [Days Until Next 1 Hour Free]
VAR target = [Days Until Next 1 Hour Free Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Book Before You Leave Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""book_before_you_leave""),
    '_Targets'[Target Value]) / 100",
    "#,##0.0%");

add("Book Before You Leave vs Target",
    @"VAR actual  = [Book Before You Leave]
VAR target  = [Book Before You Leave Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

// ── BG colour measures ───────────────────────────────────────────────────────
// chair_utilisation     → above + percent → absolute pp
// dna_rate              → below + percent → absolute pp (lower is better)
// days_until_30min_free → below + count   → relative %  (lower is better)
// days_until_1hr_free   → below + count   → relative %  (lower is better)
// book_before_you_leave → above + percent → absolute pp

add("Chair Utilisation BG",
    @"VAR actual   = [Chair Utilisation]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""chair_utilisation""), '_Targets'[Target Value]) / 100
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
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_rate""), '_Targets'[Target Value]) / 100
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
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""book_before_you_leave""), '_Targets'[Target Value]) / 100
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""book_before_you_leave""), '_Targets'[Variance])
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp >= band,   ""#1a7f3c"",
    diff_pp >= 0,          ""#6abf7b"",
    diff_pp >= -band,  ""#f4a261"",
                           ""#c0392b"")",
    "");

// ── Home Detail measures ──────────────────────────────────────────────────────
// Cancellation Frequency and Short Notice Cancellation Rate read from the
// Aggregate table (Cancelled_Appointments / Short_Notice_Cancellations columns)
// to avoid cross-table relationship dependency on _Appointments[Is Cancelled].

add("Cancellation Frequency",
    @"SUM('Aggregate Site Patient Practitioner Daily'[Cancelled Appointments])",
    "#,##0");

add("Short Notice Cancellation Rate",
    @"DIVIDE(
    SUM('Aggregate Site Patient Practitioner Daily'[Short Notice Cancellations]),
    SUM('Aggregate Site Patient Practitioner Daily'[Cancelled Appointments]))",
    "#,##0.0%");

add("Cancellation Frequency Target",
    @"MAXX(FILTER('_Targets', '_Targets'[Metric] = ""cancellation_frequency""),
    '_Targets'[Target Value])",
    "#,##0");

add("Cancellation Frequency vs Target",
    @"VAR actual = [Cancellation Frequency]
VAR target = [Cancellation Frequency Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Short Notice Cancellation Rate Target",
    @"MAXX(FILTER('_Targets', '_Targets'[Metric] = ""short_notice_cancellation_rate""),
    '_Targets'[Target Value]) / 100",
    "#,##0.0%");

add("Short Notice Cancellation Rate vs Target",
    @"VAR actual  = [Short Notice Cancellation Rate]
VAR target  = [Short Notice Cancellation Rate Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("Cancellation Frequency BG",
    @"VAR actual = [Cancellation Frequency]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""cancellation_frequency""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""cancellation_frequency""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Short Notice Cancellation Rate BG",
    @"VAR actual  = [Short Notice Cancellation Rate]
VAR target  = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""short_notice_cancellation_rate""), '_Targets'[Target Value]) / 100
VAR band    = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""short_notice_cancellation_rate""), '_Targets'[Variance])
VAR diff_pp = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp <= -band, ""#1a7f3c"",
    diff_pp <= 0,     ""#6abf7b"",
    diff_pp <= band,  ""#f4a261"",
                      ""#c0392b"")",
    "");

Info("Scheduling KPI measures created.");
