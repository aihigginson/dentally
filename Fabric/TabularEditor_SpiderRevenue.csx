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
//   *05  09/06/2026  AIH  Fix: compute actual via TREATAS so Deneb row context correctly
//                         isolates per-practitioner figures from _Invoice Items / _Payments
//   *06  09/06/2026  AIH  Fix: Plan Value denominator → practice average (not target) for
//                         meaningful per-practitioner variance; Outstanding Invoices axis
//                         replaced with per-practitioner _Invoice Items[Invoice Amount
//                         Outstanding] as snapshot-based measure cannot split by practitioner

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
    @"VAR prac_pks    = VALUES('List Practitioners'[pk Practitioner])
VAR actual      = CALCULATE(SUM('_Invoice Items'[Total Price]), TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR practice_tgt = [Total Revenue Target]
VAR n           = CALCULATE(COUNTROWS('List Practitioners'), ALLSELECTED('List Practitioners'))
VAR share       = DIVIDE(practice_tgt, n)
VAR fallback    = AVERAGEX(ALLSELECTED('List Practitioners'), [Total Revenue])
RETURN IFERROR(DIVIDE(actual, IF(share > 0, share, fallback)), 0)",
    @"0.00");

add("Spider Rev Private Revenue",
    @"VAR prac_pks    = VALUES('List Practitioners'[pk Practitioner])
VAR actual      = CALCULATE(SUM('_Invoice Items'[Total Price]), '_Invoice Items'[NHS Charge] = 0, TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR practice_tgt = [Private Revenue Target]
VAR n           = CALCULATE(COUNTROWS('List Practitioners'), ALLSELECTED('List Practitioners'))
VAR share       = DIVIDE(practice_tgt, n)
VAR fallback    = AVERAGEX(ALLSELECTED('List Practitioners'), [Private Revenue])
RETURN IFERROR(DIVIDE(actual, IF(share > 0, share, fallback)), 0)",
    @"0.00");

add("Spider Rev NHS Revenue",
    @"VAR prac_pks    = VALUES('List Practitioners'[pk Practitioner])
VAR actual      = CALCULATE(SUM('_Invoice Items'[Total Price]), '_Invoice Items'[NHS Charge] > 0, TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR practice_tgt = [NHS Revenue Target]
VAR n           = CALCULATE(COUNTROWS('List Practitioners'), ALLSELECTED('List Practitioners'))
VAR share       = DIVIDE(practice_tgt, n)
VAR fallback    = AVERAGEX(ALLSELECTED('List Practitioners'), [NHS Revenue])
RETURN IFERROR(DIVIDE(actual, IF(share > 0, share, fallback)), 0)",
    @"0.00");

// Lower-is-better: per-prac threshold / actual → >1 means below threshold (good)
// Uses _Invoice Items[Invoice Amount Outstanding] per practitioner (the snapshot-based
// [Outstanding Invoices] measure uses REMOVEFILTERS and cannot split by practitioner).
add("Spider Rev Outstanding Invoices",
    @"VAR prac_pks    = VALUES('List Practitioners'[pk Practitioner])
VAR actual      = COALESCE(
    CALCULATE(SUM('_Invoice Items'[Invoice Amount Outstanding]), TREATAS(prac_pks, '_Invoice Items'[fk Practitioner])),
    0)
VAR practice_tgt = [Outstanding Invoices Target]
VAR n           = CALCULATE(COUNTROWS('List Practitioners'), ALLSELECTED('List Practitioners'))
VAR share       = DIVIDE(practice_tgt, n)
VAR fallback    = AVERAGEX(ALLSELECTED('List Practitioners'),
    CALCULATE(SUM('_Invoice Items'[Invoice Amount Outstanding]), TREATAS(VALUES('List Practitioners'[pk Practitioner]), '_Invoice Items'[fk Practitioner])))
RETURN IF(ISBLANK(practice_tgt),
    IF(actual = 0, 2, IFERROR(DIVIDE(fallback, actual), 1)),
    IF(actual = 0, 2, IFERROR(DIVIDE(share, actual), 2)))",
    @"0.00");

// Rate: this practitioner's average plan value vs the practice-wide average.
// Delegates to [Average Plan Value] for the individual value (known-good TREATAS pattern).
// practice_avg uses ALL on all three related tables to break the residual filter chain
// that [ALLSELECTED('List Practitioners')] alone leaves in place on _Treatment Plan Items and
// List Treatment Plans — without this, every AVERAGEX iteration sees only the selected
// practitioner's plans and practice_avg collapses to actual, giving ratio = 1.0 always.
add("Spider Rev Plan Value",
    @"VAR actual       = [Average Plan Value]
VAR practice_avg = CALCULATE(
    [Average Plan Value],
    ALLSELECTED('List Practitioners'),
    ALLSELECTED('_Treatment Plan Items'),
    ALLSELECTED('List Treatment Plans')
)
RETURN IFERROR(DIVIDE(actual, IF(practice_avg > 0, practice_avg, 1)), 0)",
    @"0.00");

// Lower-is-better: target_rate / actual_rate → above target ring = fewer discounts (good)
// actual = 0 → no discounts at all → perfect score (2); BLANK → no invoice data → neutral (1)
add("Spider Rev Discounts",
    @"VAR prac_pks  = VALUES('List Practitioners'[pk Practitioner])
VAR prac_rev  = CALCULATE(SUM('_Invoice Items'[Total Price]), TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR prac_disc = CALCULATE(
    SUMX(
        SUMMARIZE('_Invoice Items',
            '_Invoice Items'[Invoice ID],
            ""_inv"",   MAX('_Invoice Items'[Invoice Amount]),
            ""_items"", SUM('_Invoice Items'[Total Price])),
        IF([_inv] > [_items], [_inv] - [_items], 0)),
    TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR actual    = DIVIDE(prac_disc, prac_rev)
VAR tgt       = [Discounts Target]
VAR fallback  = AVERAGEX(ALLSELECTED('List Practitioners'), [Discounts])
VAR denom     = IF(NOT ISBLANK(tgt), tgt, fallback)
RETURN IF(
    ISBLANK(actual), 1,
    IF(actual = 0,   2,
    IFERROR(DIVIDE(denom, actual), 1)))",
    @"0.00");

// Higher-is-better: actual_rate / target_rate → above target ring = higher deposit coverage (good)
// BLANK actual → no payment data → neutral (0 rendered as centre)
add("Spider Rev Deposit Value",
    @"VAR prac_pks = VALUES('List Practitioners'[pk Practitioner])
VAR prac_dep  = CALCULATE(SUM('_Payments'[Deposit Amount]), TREATAS(prac_pks, '_Payments'[fk Practitioner]))
VAR prac_rev  = CALCULATE(SUM('_Invoice Items'[Total Price]), TREATAS(prac_pks, '_Invoice Items'[fk Practitioner]))
VAR actual    = DIVIDE(prac_dep, prac_rev)
VAR tgt       = [Deposit Value Target]
VAR fallback  = AVERAGEX(ALLSELECTED('List Practitioners'), [Deposit Value])
VAR denom     = IF(NOT ISBLANK(tgt), tgt, IF(fallback > 0, fallback, 1))
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
    @"AVERAGEX(ALLSELECTED('List Practitioners'), [Spider Rev Total Revenue])",
    @"0.00");

add("Spider Rev Avg Private Revenue",
    @"AVERAGEX(ALLSELECTED('List Practitioners'), [Spider Rev Private Revenue])",
    @"0.00");

add("Spider Rev Avg NHS Revenue",
    @"AVERAGEX(ALLSELECTED('List Practitioners'), [Spider Rev NHS Revenue])",
    @"0.00");

add("Spider Rev Avg Outstanding Invoices",
    @"AVERAGEX(ALLSELECTED('List Practitioners'), [Spider Rev Outstanding Invoices])",
    @"0.00");

add("Spider Rev Avg Plan Value",
    @"VAR pa = CALCULATE([Average Plan Value], ALLSELECTED('List Practitioners'), ALLSELECTED('_Treatment Plan Items'), ALLSELECTED('List Treatment Plans'))
RETURN IF(pa > 0, 1, BLANK())",
    @"0.00");

add("Spider Rev Avg Discounts",
    @"AVERAGEX(ALLSELECTED('List Practitioners'), [Spider Rev Discounts])",
    @"0.00");

add("Spider Rev Avg Deposit Value",
    @"AVERAGEX(ALLSELECTED('List Practitioners'), [Spider Rev Deposit Value])",
    @"0.00");
