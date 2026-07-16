// TabularEditor_SpiderNHS.csx
// Creates 15 measures for the NHS Spider (Deneb radar) visual:
//   5  Spider NHS *       — individual values, filter-context sensitive
//   5  Spider NHS Avg *   — practice average, ALLSELECTED('List Practitioners') bypasses slicer
//   5  Spider NHS Tgt *   — targets
//
// Axes: UDA Completion Rate, NHS Revenue, Rev Per Clinical Hour, UDAs Completed, UOAs
// All axes higher-is-better.
// UDA Completion target = [NHS UDA Contracted] (the contracted figure)
// UOAs target           = [NHS UOAs Target]
//
// History:
//   *01  21/05/2026  AIH  Initial

var folder = "Spider NHS";
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

// ── Individual ────────────────────────────────────────────────────────────────

add("Spider NHS UDA Completion",
    @"IFERROR([NHS UDA Completion Rate], BLANK())",
    @"0.0%");

add("Spider NHS Revenue",
    @"[NHS Revenue]",
    @"£#,##0");

add("Spider NHS Rev Per Hour",
    @"[Revenue Per Clinical Hour]",
    @"£#,##0");

add("Spider NHS UDAs Completed",
    @"[NHS UDA Completed]",
    @"#,##0");

add("Spider NHS UOAs",
    @"[NHS UOAs]",
    @"#,##0");

// ── Targets ───────────────────────────────────────────────────────────────────

add("Spider NHS Tgt UDA Completion",
    @"IFERROR([NHS UDA Completion Rate Target], BLANK())",
    @"0.0%");

add("Spider NHS Tgt Revenue",
    @"MAXX(FILTER('_Daily Targets', '_Daily Targets'[Metric] = ""nhs_revenue"" && '_Daily Targets'[Target Level] = ""Practice""), '_Daily Targets'[Annual Target Value])",
    @"£#,##0");

add("Spider NHS Tgt Rev Per Hour",
    @"[Revenue Per Clinical Hour Target]",
    @"£#,##0");

// No single contracted target applies across multiple contracts — use average as the benchmark
add("Spider NHS Tgt UDAs Completed",
    @"CALCULATE([Spider NHS UDAs Completed], ALLSELECTED('List Practitioners'))",
    @"#,##0");

add("Spider NHS Tgt UOAs",
    @"[NHS UOAs Target]",
    @"#,##0");

// ── Practice averages (ALL bypasses practitioner slicer) ──────────────────────

add("Spider NHS Avg UDA Completion",
    @"CALCULATE([Spider NHS UDA Completion], ALLSELECTED('List Practitioners'))",
    @"0.0%");

add("Spider NHS Avg Revenue",
    @"CALCULATE([Spider NHS Revenue], ALLSELECTED('List Practitioners'))",
    @"£#,##0");

add("Spider NHS Avg Rev Per Hour",
    @"CALCULATE([Spider NHS Rev Per Hour], ALLSELECTED('List Practitioners'))",
    @"£#,##0");

add("Spider NHS Avg UDAs Completed",
    @"CALCULATE([Spider NHS UDAs Completed], ALLSELECTED('List Practitioners'))",
    @"#,##0");

add("Spider NHS Avg UOAs",
    @"CALCULATE([Spider NHS UOAs], ALLSELECTED('List Practitioners'))",
    @"#,##0");
