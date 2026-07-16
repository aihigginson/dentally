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
