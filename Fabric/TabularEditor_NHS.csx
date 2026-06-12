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
    @"VAR sel_site    = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant  = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR run_rate    = [_Period Run Rate]
VAR target_rows = FILTER(
    ALL('_Daily Targets'),
    '_Daily Targets'[Metric]             = ""nhs_udas""
    && '_Daily Targets'[fk Practitioner] = -1
    && '_Daily Targets'[Tenant ID]       = sel_tenant
    && (sel_site = -1 || '_Daily Targets'[fk Practice Site] = sel_site))
VAR full_target = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    target_rows)
RETURN IF(ISBLANK(full_target), BLANK(), full_target * run_rate)",
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
    @"VAR sel_site    = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant  = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR run_rate    = [_Period Run Rate]
VAR target_rows = FILTER(
    ALL('_Daily Targets'),
    '_Daily Targets'[Metric]             = ""nhs_uoas""
    && '_Daily Targets'[fk Practitioner] = -1
    && '_Daily Targets'[Tenant ID]       = sel_tenant
    && (sel_site = -1 || '_Daily Targets'[fk Practice Site] = sel_site))
VAR full_target = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    target_rows)
RETURN IF(ISBLANK(full_target), BLANK(), full_target * run_rate)",
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

add("NHS UDA Completion Rate Target",
    @"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""nhs_uda_completion_rate"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""nhs_uda_completion_rate"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100",
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

// ── YTD contract tracking (line chart: cumulative actuals vs cumulative target) ──
// X-axis: List Date[Week Commencing Date] filtered to a single financial year.
// Both measures use running-total logic: sum all weeks up to and including the
// current week in context. Tenant/contract filters are inherited from RLS and
// any slicers; only the date dimension is overridden for the accumulation.

add("NHS UDA Claims YTD",
    @"VAR _fy = MAX('List Date'[Financial Year])
VAR _fw = MAX('List Date'[Financial Week])
RETURN
CALCULATE(
    SUMX(
        '_NHS Claims',
        COALESCE('_NHS Claims'[Awarded UDA], '_NHS Claims'[Expected UDA])
    ),
    REMOVEFILTERS('List Date'),
    FILTER(
        ALL('List Date'),
        'List Date'[Financial Year]  = _fy
        && 'List Date'[Financial Week] <= _fw
    )
)",
    "#,##0.00");

add("NHS UDA Contract Target YTD",
    @"VAR _fy = MAX('List Date'[Financial Year])
VAR _fw = MAX('List Date'[Financial Week])
RETURN
CALCULATE(
    SUM('_NHS Contract Week'[Pro Rata UDA Target]),
    REMOVEFILTERS('List Date'),
    '_NHS Contract Week'[Financial Year]  = _fy,
    '_NHS Contract Week'[Financial Week] <= _fw
)",
    "#,##0.00");

// ── BG colour measures ───────────────────────────────────────────────────────
// nhs_udas / nhs_uoas: target and band from _Daily Targets (contract-derived).
// nhs_uda_completion_rate: target and band from _Targets (manual Input.Targets entry).

add("NHS UDAs BG",
    @"VAR actual     = [NHS UDAs]
VAR target     = [NHS UDAs Target]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR band       = CALCULATE(
    MAX('_Daily Targets'[Variance]),
    FILTER(
        ALL('_Daily Targets'),
        '_Daily Targets'[Metric]             = ""nhs_udas""
        && '_Daily Targets'[fk Practitioner] = -1
        && '_Daily Targets'[Tenant ID]       = sel_tenant
        && (sel_site = -1 || '_Daily Targets'[fk Practice Site] = sel_site)))
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
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR band       = CALCULATE(
    MAX('_Daily Targets'[Variance]),
    FILTER(
        ALL('_Daily Targets'),
        '_Daily Targets'[Metric]             = ""nhs_uoas""
        && '_Daily Targets'[fk Practitioner] = -1
        && '_Daily Targets'[Tenant ID]       = sel_tenant
        && (sel_site = -1 || '_Daily Targets'[fk Practice Site] = sel_site)))
VAR pct        = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),   ""#FFFFFF"",
    pct >= band,       ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,      ""#f4a261"",
                       ""#c0392b"")",
    "");

add("NHS UDA Completion Rate BG",
    @"VAR actual   = [NHS UDA Completion Rate]
VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_tenant = SELECTEDVALUE('List Practice Sites'[Tenant ID])
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""nhs_uda_completion_rate"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""nhs_uda_completion_rate"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value])) / 100
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""nhs_uda_completion_rate"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Tenant ID] = sel_tenant && '_Targets'[Metric] = ""nhs_uda_completion_rate"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),       ""#FFFFFF"",
    diff_pp >= band,   ""#1a7f3c"",
    diff_pp >= 0,          ""#6abf7b"",
    diff_pp >= -band,  ""#f4a261"",
                           ""#c0392b"")",
    "");

Info("NHS KPI measures created.");
