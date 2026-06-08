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
// Rate/point-in-time axes (Plan Value, Discounts, Deposit Value):
//   Target from _Effective Targets is site-level — same threshold for all practitioners.
//   Fallback when no target: individual = actual / practice_average.
//   Plan Value routes via _Treatment Plan Items[fk_Practitioner] → plan value on List Treatment Plans.
//   (List Treatment Plans[Practitioner_ID] is a raw int with no PBI relationship.)
//
// Lower-is-better inversion (Outstanding Inv, Discounts):
//   Individual = target / actual  → above target ring = below threshold (good).
//   actual = 0 → perfect → return 2 (capped max).  BLANK → no data → return 1 (neutral).
//
// History:
//   *01  21/05/2026  AIH  Initial
//   *02  21/05/2026  AIH  AVERAGEX + avg-fallback for axes without _Targets entries
//   *03  21/05/2026  AIH  Ratio architecture: all individual = ratio vs per-prac target
//   *04  08/06/2026  AIH  Real DAX for Discounts and Deposit Value (was hardcoded 1)

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

// Rate: average private value of plans this practitioner has items on.
// Route via _Treatment Plan Items (has fk_Practitioner) → List Treatment Plans (has Private Treatment Value).
// Filter to Private Treatment Value > 0 to exclude NHS plans with £0 value.
add("Spider Rev Plan Value",
    @"VAR _plan_vals =
    FILTER(
        ADDCOLUMNS(
            DISTINCT('_Treatment Plan Items'[fk Treatment Plan]),
            ""_pv"", CALCULATE(MAX('List Treatment Plans'[Private Treatment Value]))
        ),
        [_pv] > 0
    )
VAR actual   = AVERAGEX(_plan_vals, [_pv])
VAR fallback = AVERAGEX(
    ALL('List Practitioners'),
    AVERAGEX(
        FILTER(
            ADDCOLUMNS(
                DISTINCT('_Treatment Plan Items'[fk Treatment Plan]),
                ""_pv"", CALCULATE(MAX('List Treatment Plans'[Private Treatment Value]))
            ),
            [_pv] > 0
        ), [_pv]))
VAR tgt      = [Average Plan Value Target]
RETURN IFERROR(DIVIDE(actual, IF(ISBLANK(tgt), fallback, tgt)), 0)",
    @"0.00");

// Lower-is-better: target_rate / actual_rate → above target ring = fewer discounts (good)
// actual = 0 → no discounts at all → perfect score (2); BLANK → no invoice data → neutral (1)
add("Spider Rev Discounts",
    @"VAR actual   = [Discounts]
VAR tgt      = [Discounts Target]
VAR fallback = AVERAGEX(ALL('List Practitioners'), [Discounts])
VAR denom    = IF(NOT ISBLANK(tgt), tgt, fallback)
RETURN IF(
    ISBLANK(actual), 1,
    IF(actual = 0,   2,
    IFERROR(DIVIDE(denom, actual), 1)))",
    @"0.00");

// Higher-is-better: actual_rate / target_rate → above target ring = higher deposit coverage (good)
// BLANK actual → no payment data → neutral (0 rendered as centre)
add("Spider Rev Deposit Value",
    @"VAR actual   = [Deposit Value]
VAR tgt      = [Deposit Value Target]
VAR fallback = AVERAGEX(ALL('List Practitioners'), [Deposit Value])
VAR denom    = IF(NOT ISBLANK(tgt), tgt, IF(fallback > 0, fallback, 1))
RETURN IFERROR(DIVIDE(actual, denom), 0)",
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
    @"AVERAGEX(ALL('List Practitioners'), [Spider Rev Discounts])",
    @"0.00");

add("Spider Rev Avg Deposit Value",
    @"AVERAGEX(ALL('List Practitioners'), [Spider Rev Deposit Value])",
    @"0.00");
