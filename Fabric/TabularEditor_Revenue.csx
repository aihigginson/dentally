var t = Model.Tables["_Measures"];
var g = "Revenue KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Value measures ───────────────────────────────────────────────────────────
// Revenue source: _Invoice Items[Total Price] (item-level price x qty)
// NHS split:      NHS Charge > 0 flags NHS items (stored as 0.00 / 1.00 in Gold)
// Outstanding:    Invoice Amount Outstanding is invoice-level — deduplicate by Invoice ID
// Note: Total Deposits / Deposit Ratio removed — no item-type column in the schema

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
    @"SUMX(
    SUMMARIZE('_Invoice Items',
        '_Invoice Items'[Invoice ID],
        ""_oa"", MAX('_Invoice Items'[Invoice Amount Outstanding])),
    [_oa])",
    "£#,##0");

add("Revenue Per Patient",
    @"DIVIDE([Total Revenue], [Active Patients])",
    "£#,##0");

add("Revenue Per Hour",
    @"VAR by_prac_day =
    SUMMARIZE(
        'Aggregate Site Patient Practitioner Daily',
        'Aggregate Site Patient Practitioner Daily'[fk Practitioner],
        'Aggregate Site Patient Practitioner Daily'[fk Date],
        ""WH"", MAX('Aggregate Site Patient Practitioner Daily'[Worked Hours]))
VAR total_worked = SUMX(by_prac_day, [WH])
RETURN DIVIDE([Total Revenue], total_worked)",
    "£#,##0");

// ── Target helper ────────────────────────────────────────────────────────────

add("_Revenue Target",
    @"VAR tbl = FILTER('_Targets',
    '_Targets'[Metric] = ""total_revenue""
    && '_Targets'[Period Type] = ""all_time"")
RETURN MAXX(tbl, '_Targets'[Target Value])",
    "");

// ── BG colour measures ───────────────────────────────────────────────────────
// currency/count metrics → relative %  (pct = (actual-target)/|target| * 100)
// above range: pct >= band = strong green … pct < -band = strong red

add("Total Revenue BG",
    @"VAR actual   = [Total Revenue]
VAR target   = [_Revenue Target]
VAR band     = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""total_revenue""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

add("NHS Revenue BG",
    @"VAR actual   = [NHS Revenue]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_revenue""), '_Targets'[Target Value])
VAR band     = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_revenue""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Private Revenue BG",
    @"VAR actual   = [Private Revenue]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""private_revenue""), '_Targets'[Target Value])
VAR band     = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""private_revenue""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Outstanding Invoices BG",
    @"VAR actual   = [Outstanding Invoices]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices""), '_Targets'[Target Value])
VAR band     = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Revenue Per Patient BG",
    @"VAR actual   = [Revenue Per Patient]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient""), '_Targets'[Target Value])
VAR band     = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Revenue Per Hour BG",
    @"VAR actual   = [Revenue Per Hour]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_hour""), '_Targets'[Target Value])
VAR band     = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_hour""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

Info("Revenue KPI measures created.");
