// TabularEditor_PractitionerSpider.csx
// Creates 14 measures for the Practitioner Spider (Deneb radar) visual:
//   7  Spider *       — individual values, filter-context sensitive (practitioner slicer applies)
//   7  Spider Avg *   — practice average, ALL('List Practitioners') bypasses practitioner slicer
//
// Vega spec logic:
//   - Average web always shown (#8AB5B2 teal)
//   - Selected web shown only when exactly 1 practitioner is selected (#1A527A navy)
//   - Both webs normalised on the same scale (best value = outer ring)
//
// PBI visual setup:
//   1. Add a Deneb visual to Home page 3.
//   2. Fields: List Practitioners[Practitioner Name]
//              + all 7 Spider * measures
//              + all 7 Spider Avg * measures
//   3. Paste Deneb_PractitionerSpider.json as the Vega spec.
//
// History:
//   *01  21/05/2026  AIH  Initial
//   *02  21/05/2026  AIH  Add Spider Avg * measures; rework to average + selected pattern

var folder = "Practitioner Spider";
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

// ── Individual axis measures (respect practitioner filter context) ──────────

add("Spider Revenue vs Target",
    @"VAR actual = [Total Revenue]
VAR target = [Total Revenue Target]
RETURN DIVIDE(actual, target)",
    @"0.0%");

add("Spider Chair Utilisation",
    @"[Chair Utilisation]",
    @"0.0%");

add("Spider Rev Per Hour",
    @"[Revenue Per Clinical Hour]",
    @"£#,##0");

add("Spider New Patients",
    @"[New Patients]",
    @"#,##0");

add("Spider Tx Conversion",
    @"[Treatment Acceptance Rate]",
    @"0.0%");

add("Spider DNA Score",
    @"VAR r = [DNA Rate]
RETURN IF(ISBLANK(r), BLANK(), 1 - r)",
    @"0.0%");

add("Spider UDA Completion",
    @"IFERROR([NHS UDA Completion Rate], BLANK())",
    @"0.0%");

// ── Target measures (what each axis is aimed at; same units as individual) ──
// Spider Revenue vs Target is already a ratio — its target is always 1.0
add("Spider Target Revenue vs Target",
    @"IF(ISBLANK([Total Revenue Target]), BLANK(), 1)",
    @"0.0%");

add("Spider Target Chair Utilisation",
    @"[Chair Utilisation Target]",
    @"0.0%");

add("Spider Target Rev Per Hour",
    @"[Revenue Per Clinical Hour Target]",
    @"£#,##0");

add("Spider Target New Patients",
    @"[New Patients Target]",
    @"#,##0");

add("Spider Target Tx Conversion",
    @"[Treatment Acceptance Rate Target]",
    @"0.0%");

add("Spider Target DNA Score",
    @"VAR r = [DNA Rate Target]
RETURN IF(ISBLANK(r), BLANK(), 1 - r)",
    @"0.0%");

add("Spider Target UDA Completion",
    @"IFERROR([NHS UDA Completion Rate Target], BLANK())",
    @"0.0%");

// ── Practice average measures (ALL bypasses practitioner slicer) ────────────

add("Spider Avg Revenue vs Target",
    @"CALCULATE([Spider Revenue vs Target], ALL('List Practitioners'))",
    @"0.0%");

add("Spider Avg Chair Utilisation",
    @"CALCULATE([Spider Chair Utilisation], ALL('List Practitioners'))",
    @"0.0%");

add("Spider Avg Rev Per Hour",
    @"CALCULATE([Spider Rev Per Hour], ALL('List Practitioners'))",
    @"£#,##0");

add("Spider Avg New Patients",
    @"CALCULATE([Spider New Patients], ALL('List Practitioners'))",
    @"#,##0");

add("Spider Avg Tx Conversion",
    @"CALCULATE([Spider Tx Conversion], ALL('List Practitioners'))",
    @"0.0%");

add("Spider Avg DNA Score",
    @"CALCULATE([Spider DNA Score], ALL('List Practitioners'))",
    @"0.0%");

add("Spider Avg UDA Completion",
    @"CALCULATE([Spider UDA Completion], ALL('List Practitioners'))",
    @"0.0%");
