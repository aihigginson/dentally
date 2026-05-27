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
VAR fy_working = CALCULATE(
    COUNTROWS('List Date'),
    'List Date'[Financial Year Name] = period_key,
    'List Date'[Is Weekend] = FALSE(),
    'List Date'[Is England Wales Bank Holiday] = FALSE(),
    ALL('List Date'))
VAR elapsed = CALCULATE(
    COUNTROWS('List Date'),
    'List Date'[Financial Year Name] = period_key,
    'List Date'[Full Date] <= TODAY(),
    'List Date'[Is Weekend] = FALSE(),
    'List Date'[Is England Wales Bank Holiday] = FALSE(),
    ALL('List Date'))
RETURN IF(is_ytd && fy_working > 0, DIVIDE(elapsed, fy_working), 1.0)",
    "");

// ── _Is Practitioner Filtered ─────────────────────────────────────────────────
// Returns 1 when the practitioner slicer has a selection, 0 otherwise.
// Used to show ⚠ in variance text for Supports_Practitioner = 0 metrics.

add("_Is Practitioner Filtered",
    @"IF(ISFILTERED('List Practitioners'[pk Practitioner]), 1, 0)",
    "");

// ── _Target FY Key ────────────────────────────────────────────────────────────
// Returns the FY key to use for target lookups.
// When an FY grouping is selected: returns that key, e.g. "FY 2025-26".
// When a non-FY grouping is selected (Last 12M, Last 3M): falls back to the
// current financial year so cards always show a relevant target.

add("_Target FY Key",
    @"VAR selected = [_FY Period Key]
VAR fy_year  = IF(MONTH(TODAY()) >= 4, YEAR(TODAY()), YEAR(TODAY()) - 1)
VAR cur_fy   = ""FY "" & fy_year & ""-"" & RIGHT("""" & (fy_year + 1), 2)
RETURN IF(selected <> """", selected, cur_fy)",
    "");

Info("Period helper measures created. Run this script once before any tab script.");
