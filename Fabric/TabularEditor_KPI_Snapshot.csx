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
// Point-in-time snapshot metric: value of uninvoiced treatment plan items on
// plans that were open at the snapshot date.
//
// Card measure  — semi-additive: picks the latest snapshot date in the current
//                 slicer selection so the card always shows one value.
// Trend measure — plain SUM: the date-axis context in a chart already restricts
//                 to a single snapshot date per point; add a visual filter
//                 Snapshot Grain = "monthly" for clean month-end series.

add("Open Courses Value",
    @"VAR last_date =
    MAXX( ALLSELECTED( '_KPI Snapshot' ), '_KPI Snapshot'[fk Date] )
RETURN
CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[fk Date] = last_date,
    '_KPI Snapshot'[Metric]  = ""open_courses_value""
)",
    "£#,##0");

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
