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
// Rate/point-in-time axes (Plan Value):
//   Target from _Targets is already per-practitioner — use directly.
//
// Dummy axes (Discounts, Deposit Value):
//   Return 1 (neutral, at target ring) until real data exists.
//
// Lower-is-better inversion (Outstanding Inv):
//   Individual = per_prac_target / actual  → above target ring = below threshold (good).
//
// History:
//   *01  21/05/2026  AIH  Initial
//   *02  21/05/2026  AIH  AVERAGEX + avg-fallback for axes without _Targets entries
//   *03  21/05/2026  AIH  Ratio architecture: all individual = ratio vs per-prac target

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
    @"VAR practice_tgt = [Total Revenue Target]
VAR n        = CALCULATE(COUNTROWS('List Practitioners'), ALL('List Practitioners'))
VAR share    = DIVIDE(practice_tgt, n)
VAR fallback = AVERAGEX(ALL('List Practitioners'), [Total Revenue])
RETURN IFERROR(DIVIDE([Total Revenue], IF(share > 0, share, fallback)), 0)",
    @"0.00");

add("Spider Rev Private Revenue",
    @"VAR practice_tgt = [Private Revenue Target]
VAR n        = CALCULATE(COUNTROWS('List Practitioners'), ALL('List Practitioners'))
VAR share    = DIVIDE(practice_tgt, n)
VAR fallback = AVERAGEX(ALL('List Practitioners'), [Private Revenue])
RETURN IFERROR(DIVIDE([Private Revenue], IF(share > 0, share, fallback)), 0)",
    @"0.00");

add("Spider Rev NHS Revenue",
    @"VAR practice_tgt = [NHS Revenue Target]
VAR n        = CALCULATE(COUNTROWS('List Practitioners'), ALL('List Practitioners'))
VAR share    = DIVIDE(practice_tgt, n)
VAR fallback = AVERAGEX(ALL('List Practitioners'), [NHS Revenue])
RETURN IFERROR(DIVIDE([NHS Revenue], IF(share > 0, share, fallback)), 0)",
    @"0.00");

// Lower-is-better: per-prac threshold / actual → >1 means below threshold (good)
// actual=0 (zero debt) is a perfect score → return 2 (capped max)
add("Spider Rev Outstanding Invoices",
    @"VAR practice_tgt = [Outstanding Invoices Target]
VAR n        = CALCULATE(COUNTROWS('List Practitioners'), ALL('List Practitioners'))
VAR share    = DIVIDE(practice_tgt, n)
VAR fallback = AVERAGEX(ALL('List Practitioners'), [Outstanding Invoices])
VAR actual   = COALESCE([Outstanding Invoices], 0)
RETURN IF(ISBLANK(practice_tgt),
    IF(actual = 0, 2, IFERROR(DIVIDE(fallback, actual), 1)),
    IF(actual = 0, 2, IFERROR(DIVIDE(share, actual), 2)))",
    @"0.00");

// Rate: target from _Targets is per-practitioner already
add("Spider Rev Plan Value",
    @"VAR tgt      = [Average Plan Value Target]
VAR fallback = AVERAGEX(ALL('List Practitioners'), [Average Plan Value])
RETURN IFERROR(DIVIDE([Average Plan Value], IF(ISBLANK(tgt), fallback, tgt)), 0)",
    @"0.00");

// Dummy — returns 1 (neutral, at target ring) until real data flows
add("Spider Rev Discounts",
    @"1",
    @"0.00");

// Dummy — returns 1 (neutral, at target ring) until deposit data available
add("Spider Rev Deposit Value",
    @"1",
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
    @"AVERAGEX(ALL('List Practitioners'), [Spider Rev Total Revenue])",
    @"0.00");

add("Spider Rev Avg Private Revenue",
    @"AVERAGEX(ALL('List Practitioners'), [Spider Rev Private Revenue])",
    @"0.00");

add("Spider Rev Avg NHS Revenue",
    @"AVERAGEX(ALL('List Practitioners'), [Spider Rev NHS Revenue])",
    @"0.00");

add("Spider Rev Avg Outstanding Invoices",
    @"AVERAGEX(ALL('List Practitioners'), [Spider Rev Outstanding Invoices])",
    @"0.00");

add("Spider Rev Avg Plan Value",
    @"AVERAGEX(ALL('List Practitioners'), [Spider Rev Plan Value])",
    @"0.00");

add("Spider Rev Avg Discounts",
    @"1",
    @"0.00");

add("Spider Rev Avg Deposit Value",
    @"1",
    @"0.00");
