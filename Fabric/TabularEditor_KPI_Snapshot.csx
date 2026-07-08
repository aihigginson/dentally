var t = Model.Tables["_Measures"];
var g = "Clinical KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Open Courses Value ─────────────────────────────────────────────────
// The current-state CARD "Open Courses Value" is now owned by TabularEditor_Clinical.csx
// (live off Gold.Fact_Treatment_Plans -> [Private Treatment Value Outstanding], the item
// roll-up). It is NOT defined here any more -- both scripts share the "Clinical KPIs"
// folder + delete-first, so defining it in both made the card depend on run order.
//
// This script keeps the HISTORICAL series only (Trend / Target / vs / BG). NB: the snapshot
// history was captured under the OLD open_courses_value definition, so the Trend line and the
// live card measure are not strictly like-for-like until the snapshot metric is rebuilt.
// Trend measure — plain SUM: the date-axis context in a chart already restricts
//                 to a single snapshot date per point; add a visual filter
//                 Snapshot Grain = "monthly" for clean month-end series.

add("Open Courses Value Trend",
    @"CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[Metric] = ""open_courses_value""
)",
    "£#,##0");

add("Open Courses Value Target",
    @"MAXX(
    FILTER( '_Targets', '_Targets'[Metric] = ""open_courses_value"" ),
    '_Targets'[Target Value])",
    "£#,##0");

add("Open Courses Value vs Target",
    @"VAR actual = [Open Courses Value]
VAR target = [Open Courses Value Target]
VAR pct    = DIVIDE( actual - target, ABS( target ) ) * 100
RETURN IF(
    ISBLANK( target ), BLANK(),
    IF( pct >= 0,
        ""▲ "" & FORMAT( pct,      ""0.0"" ) & ""%"",
        ""▼ "" & FORMAT( ABS(pct), ""0.0"" ) & ""%"" ))",
    "");

add("Open Courses Value BG",
    @"VAR actual = [Open Courses Value]
VAR target = MAXX( FILTER( '_Targets', '_Targets'[Metric] = ""open_courses_value"" ), '_Targets'[Target Value] )
VAR band   = MAXX( FILTER( '_Targets', '_Targets'[Metric] = ""open_courses_value"" ), '_Targets'[Variance] )
VAR pct    = DIVIDE( actual - target, ABS( target ) ) * 100
RETURN SWITCH( TRUE(),
    ISBLANK( target ), ""#FFFFFF"",
    pct >= band,       ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,      ""#f4a261"",
                       ""#c0392b"" )",
    "");

Info("Clinical KPI measures created.");
