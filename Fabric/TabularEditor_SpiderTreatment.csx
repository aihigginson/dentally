// TabularEditor_SpiderTreatment.csx
// Creates 15 measures for the Treatment Spider (Deneb radar) visual:
//   5  Spider Tx *       — individual values, filter-context sensitive
//   5  Spider Tx Avg *   — practice average, ALL('List Practitioners') bypasses slicer
//   5  Spider Tx Tgt *   — targets (inverted axes return ratio sentinel 1)
//
// Lower-is-better axis (Open Courses):
//   Individual = DIVIDE(target, actual) — ratio where >1 means fewer courses (good)
//   Target     = IF(ISBLANK(target), BLANK(), 1)
//
// History:
//   *01  21/05/2026  AIH  Initial

var folder = "Spider Treatment";
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

add("Spider Tx Rev Per Hour",
    @"[Revenue Per Clinical Hour]",
    @"£#,##0");

add("Spider Tx Open Courses Value",
    @"[Open Courses Value]",
    @"£#,##0");

// Lower-is-better: fewer open courses = better
add("Spider Tx Open Courses",
    @"VAR tgt = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""open_courses""), '_Targets'[Target Value])
RETURN IFERROR(DIVIDE(tgt, [Open Courses]), 2)",
    @"0.00");

add("Spider Tx Exam Ratio",
    @"[Exam Ratio]",
    @"0.0%");

add("Spider Tx Acceptance Rate",
    @"[Treatment Acceptance Rate]",
    @"0.0%");

// ── Targets ───────────────────────────────────────────────────────────────────

add("Spider Tx Tgt Rev Per Hour",
    @"[Revenue Per Clinical Hour Target]",
    @"£#,##0");

add("Spider Tx Tgt Open Courses Value",
    @"MAXX(FILTER('_Targets', '_Targets'[Metric] = ""open_courses_value""), '_Targets'[Target Value])",
    @"£#,##0");

// Inverted sentinel
add("Spider Tx Tgt Open Courses",
    @"VAR tgt = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""open_courses""), '_Targets'[Target Value])
RETURN IF(ISBLANK(tgt), BLANK(), 1)",
    @"0.00");

add("Spider Tx Tgt Exam Ratio",
    @"[Exam Ratio Target]",
    @"0.0%");

add("Spider Tx Tgt Acceptance Rate",
    @"[Treatment Acceptance Rate Target]",
    @"0.0%");

// ── Practice averages (ALL bypasses practitioner slicer) ──────────────────────

add("Spider Tx Avg Rev Per Hour",
    @"CALCULATE([Spider Tx Rev Per Hour], ALL('List Practitioners'))",
    @"£#,##0");

add("Spider Tx Avg Open Courses Value",
    @"CALCULATE([Spider Tx Open Courses Value], ALL('List Practitioners'))",
    @"£#,##0");

add("Spider Tx Avg Open Courses",
    @"CALCULATE([Spider Tx Open Courses], ALL('List Practitioners'))",
    @"0.00");

add("Spider Tx Avg Exam Ratio",
    @"CALCULATE([Spider Tx Exam Ratio], ALL('List Practitioners'))",
    @"0.0%");

add("Spider Tx Avg Acceptance Rate",
    @"CALCULATE([Spider Tx Acceptance Rate], ALL('List Practitioners'))",
    @"0.0%");
