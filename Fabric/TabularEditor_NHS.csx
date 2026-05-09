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

// UDA completion: UDAs delivered vs contracted (from treatment plan UDA values)
add("NHS UDA Contracted",
    @"SUM('List Treatment Plans'[NHS UDA Value])",
    "#,##0.00");

add("NHS UDA Completed",
    @"SUM('List Treatment Plans'[NHS Completed UDA Value])",
    "#,##0.00");

add("NHS UDA Completion Rate",
    @"DIVIDE(
    SUM('List Treatment Plans'[NHS Completed UDA Value]),
    SUM('List Treatment Plans'[NHS UDA Value]))",
    "#,##0.0%");

// NHS Revenue is defined in the Revenue KPIs folder; reference it here for
// convenience on the NHS report page without duplicating the formula.
// If you need a standalone copy, uncomment and rename below.
// add("NHS Revenue (NHS)", @"[NHS Revenue]", ""£#,##0"");

// ── BG colour measures ───────────────────────────────────────────────────────
// No _Targets rows exist for NHS metrics yet — all return white.
// Add rows to _Targets with the metric keys below and these will light up:
//   nhs_udas | nhs_uoas | nhs_uda_completion_rate

add("NHS UDAs BG",
    @"VAR actual   = [NHS UDAs]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_udas""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_udas""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct >= band,   ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,  ""#f4a261"",
                       ""#c0392b"")",
    "");

add("NHS UOAs BG",
    @"VAR actual   = [NHS UOAs]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_uoas""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_uoas""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct >= band,   ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,  ""#f4a261"",
                       ""#c0392b"")",
    "");

add("NHS UDA Completion Rate BG",
    @"VAR actual   = [NHS UDA Completion Rate]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_uda_completion_rate""), '_Targets'[Target Value])
VAR band = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_uda_completion_rate""), '_Targets'[Variance])
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp >= band,   ""#1a7f3c"",
    diff_pp >= 0,          ""#6abf7b"",
    diff_pp >= -band,  ""#f4a261"",
                           ""#c0392b"")",
    "");

Info("NHS KPI measures created.");
