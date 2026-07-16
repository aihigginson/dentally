// TabularEditor_RestoreOpenCourses.csx
// TARGETED restore of the 8 Open Courses measures with their EXACT original names + DAX + folders.
// Idempotent: deletes any existing same-named measure first, then re-adds. Touches nothing else.
// Run once in Tabular Editor, then save. Cards reference measures by name -> they re-bind, no rework.
var t = Model.Tables["_Measures"];
Action<string,string,string,string> put = (name, dax, fmt, folder) => {
    foreach (var ex in t.Measures.Where(m => m.Name == name).ToList()) ex.Delete();
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = folder;
    if (fmt != "") m.FormatString = fmt;
};
put("Open Courses",
    @"CALCULATE(
    COUNTROWS('_Treatment Plans'),
    '_Treatment Plans'[Course Status] IN { ""In Progress"", ""Open - No Appointment"" }
)",
    "#,##0", "Clinical KPIs");
put("Open Courses Without Appointment",
    @"CALCULATE(
    COUNTROWS('_Treatment Plans'),
    '_Treatment Plans'[Course Status] = ""Open - No Appointment""
)",
    "#,##0", "Clinical KPIs");
put("Open Courses Without Appointment Value",
    @"CALCULATE(
    SUM('_Treatment Plans'[Private Treatment Value Outstanding]),
    '_Treatment Plans'[Course Status] = ""Open - No Appointment""
)",
    "£#,##0", "Clinical KPIs");
put("Open Courses Value",
    @"CALCULATE(
    SUM('_Treatment Plans'[Private Treatment Value Outstanding]),
    '_Treatment Plans'[Course Status] IN { ""In Progress"", ""Open - No Appointment"" }
)",
    "£#,##0", "Clinical KPIs");
put("Open Courses Value Trend",
    @"CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[Metric] = ""open_courses_value""
)",
    "£#,##0", "Clinical KPIs");
put("Open Courses Value Target",
    @"MAXX(
    FILTER( '_Daily Targets', '_Daily Targets'[Metric] = ""open_courses_value"" && '_Daily Targets'[Target Level] = ""Practice"" ),
    '_Daily Targets'[Annual Target Value])",
    "£#,##0", "Clinical KPIs");
put("Open Courses Value vs Target",
    @"VAR actual = [Open Courses Value]
VAR target = [Open Courses Value Target]
VAR pct    = DIVIDE( actual - target, ABS( target ) ) * 100
RETURN IF(
    ISBLANK( target ), BLANK(),
    IF( pct >= 0,
        ""▲ "" & FORMAT( pct,      ""0.0"" ) & ""%"",
        ""▼ "" & FORMAT( ABS(pct), ""0.0"" ) & ""%"" ))",
    "", "Clinical KPIs");
put("Open Courses Value BG",
    @"VAR actual = [Open Courses Value]
VAR target = MAXX( FILTER( '_Daily Targets', '_Daily Targets'[Metric] = ""open_courses_value"" && '_Daily Targets'[Target Level] = ""Practice"" ), '_Daily Targets'[Annual Target Value] )
VAR band   = MAXX( FILTER( '_Daily Targets', '_Daily Targets'[Metric] = ""open_courses_value"" && '_Daily Targets'[Target Level] = ""Practice"" ), '_Daily Targets'[Variance] )
VAR pct    = DIVIDE( actual - target, ABS( target ) ) * 100
RETURN SWITCH( TRUE(),
    ISBLANK( target ), ""#FFFFFF"",
    pct >= band,       ""#1a7f3c"",
    pct >= 0,          ""#6abf7b"",
    pct >= -band,      ""#f4a261"",
                       ""#c0392b"" )",
    "", "Clinical KPIs");
Info("Restored 8 Open Courses measures.");
