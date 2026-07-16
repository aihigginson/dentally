// TabularEditor_SpiderScheduling.csx
// Creates 21 measures for the Scheduling Spider (Deneb radar) visual:
//   7  Spider Sch *       — individual values, filter-context sensitive
//   7  Spider Sch Avg *   — practice average, ALLSELECTED('List Practitioners') bypasses slicer
//   7  Spider Sch Tgt *   — targets (inverted axes return ratio sentinel 1)
//
// Lower-is-better axes (Cancellation Freq, Short Notice Cancel, Days Next 30/1Hr):
//   Individual = DIVIDE(target, actual)  — ratio where >1 means better than target
//   Target     = IF(ISBLANK(target), BLANK(), 1)
//
// History:
//   *01  21/05/2026  AIH  Initial

var folder = "Spider Scheduling";
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

add("Spider Sch Chair Utilisation",
    @"[Chair Utilisation]",
    @"0.0%");

// DNA Score: higher is better (1 - DNA rate)
add("Spider Sch DNA Score",
    @"VAR r = [DNA Rate]
RETURN IF(ISBLANK(r), BLANK(), 1 - r)",
    @"0.0%");

// Lower-is-better: fewer cancellations = better
add("Spider Sch Cancellation Freq",
    @"VAR tgt = MAXX(FILTER('_Daily Targets', '_Daily Targets'[Metric] = ""cancellation_frequency"" && '_Daily Targets'[Target Level] = ""Practice""), '_Daily Targets'[Annual Target Value])
RETURN IFERROR(DIVIDE(tgt, [Cancellation Frequency]), 2)",
    @"0.00");

// Lower-is-better: dummy until Short Notice Cancellation Rate has real data
add("Spider Sch Short Notice Cancel",
    @"VAR tgt = MAXX(FILTER('_Daily Targets', '_Daily Targets'[Metric] = ""short_notice_cancellation_rate"" && '_Daily Targets'[Target Level] = ""Practice""), '_Daily Targets'[Annual Target Value])
RETURN IFERROR(DIVIDE(tgt, [Short Notice Cancellation Rate]), 2)",
    @"0.00");

add("Spider Sch BBYL",
    @"[Book Before You Leave]",
    @"0.0%");

// Lower-is-better: fewer days wait is better
add("Spider Sch Days Next 30 Min",
    @"VAR tgt = MAXX(FILTER('_Daily Targets', '_Daily Targets'[Metric] = ""days_until_30min_free"" && '_Daily Targets'[Target Level] = ""Practice""), '_Daily Targets'[Annual Target Value])
RETURN IFERROR(DIVIDE(tgt, [Days Until Next 30 Minute Free]), 2)",
    @"0.00");

// ── Targets ───────────────────────────────────────────────────────────────────

add("Spider Sch Tgt Chair Utilisation",
    @"[Chair Utilisation Target]",
    @"0.0%");

add("Spider Sch Tgt DNA Score",
    @"VAR r = [DNA Rate Target]
RETURN IF(ISBLANK(r), BLANK(), 1 - r)",
    @"0.0%");

// Inverted sentinels
add("Spider Sch Tgt Cancellation Freq",
    @"VAR tgt = MAXX(FILTER('_Daily Targets', '_Daily Targets'[Metric] = ""cancellation_frequency"" && '_Daily Targets'[Target Level] = ""Practice""), '_Daily Targets'[Annual Target Value])
RETURN IF(ISBLANK(tgt), BLANK(), 1)",
    @"0.00");

add("Spider Sch Tgt Short Notice Cancel",
    @"VAR tgt = MAXX(FILTER('_Daily Targets', '_Daily Targets'[Metric] = ""short_notice_cancellation_rate"" && '_Daily Targets'[Target Level] = ""Practice""), '_Daily Targets'[Annual Target Value])
RETURN IF(ISBLANK(tgt), BLANK(), 1)",
    @"0.00");

add("Spider Sch Tgt BBYL",
    @"[Book Before You Leave Target]",
    @"0.0%");

add("Spider Sch Tgt Days Next 30 Min",
    @"VAR tgt = MAXX(FILTER('_Daily Targets', '_Daily Targets'[Metric] = ""days_until_30min_free"" && '_Daily Targets'[Target Level] = ""Practice""), '_Daily Targets'[Annual Target Value])
RETURN IF(ISBLANK(tgt), BLANK(), 1)",
    @"0.00");

// ── Practice averages (ALL bypasses practitioner slicer) ──────────────────────

add("Spider Sch Avg Chair Utilisation",
    @"CALCULATE([Spider Sch Chair Utilisation], ALLSELECTED('List Practitioners'))",
    @"0.0%");

add("Spider Sch Avg DNA Score",
    @"CALCULATE([Spider Sch DNA Score], ALLSELECTED('List Practitioners'))",
    @"0.0%");

add("Spider Sch Avg Cancellation Freq",
    @"CALCULATE([Spider Sch Cancellation Freq], ALLSELECTED('List Practitioners'))",
    @"0.00");

add("Spider Sch Avg Short Notice Cancel",
    @"CALCULATE([Spider Sch Short Notice Cancel], ALLSELECTED('List Practitioners'))",
    @"0.00");

add("Spider Sch Avg BBYL",
    @"CALCULATE([Spider Sch BBYL], ALLSELECTED('List Practitioners'))",
    @"0.0%");

add("Spider Sch Avg Days Next 30 Min",
    @"CALCULATE([Spider Sch Days Next 30 Min], ALLSELECTED('List Practitioners'))",
    @"0.00");
