var t = Model.Tables["_Measures"];
var g = "_Period Helpers";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── _FY Period Key ────────────────────────────────────────────────────────────
// Returns the FY key without "(YTD)" suffix, e.g. "FY 2026/27".
// Returns "" when no FY filter is active (all-time, Last 12 Months, etc.).

add("_FY Period Key",
    @"VAR raw = SELECTEDVALUE('List Date Grouping'[Date Grouping], """")
RETURN IF(LEFT(raw, 2) = ""FY"", SUBSTITUTE(raw, "" (YTD)"", """"), """")",
    "");

// ── _Period Run Rate ──────────────────────────────────────────────────────────
// Returns the fraction of the financial year's working days that have elapsed.
// = 1.0 when no YTD filter is active (full-year or all-time view).
// Used to prorate annual targets against actual YTD working days.

add("_Period Run Rate",
    @"VAR period_key = [_FY Period Key]
VAR raw        = SELECTEDVALUE('List Date Grouping'[Date Grouping], """")
VAR is_ytd     = CONTAINSSTRING(raw, ""(YTD)"")
VAR fy_name    = SUBSTITUTE(period_key, "" "", """")
VAR fy_working = CALCULATE(
    COUNTROWS('List Date'),
    'List Date'[Financial Year Name] = fy_name,
    'List Date'[Is Weekend] = FALSE(),
    'List Date'[Is England Wales Bank Holiday] = FALSE(),
    ALL('List Date'))
VAR elapsed = CALCULATE(
    COUNTROWS('List Date'),
    'List Date'[Financial Year Name] = fy_name,
    'List Date'[Full Date] <= TODAY(),
    'List Date'[Is Weekend] = FALSE(),
    'List Date'[Is England Wales Bank Holiday] = FALSE(),
    ALL('List Date'))
RETURN IF(is_ytd && fy_working > 0, DIVIDE(elapsed, fy_working), 1.0)",
    "");

Info("Period helper measures created. Run this script once before any tab script.");
