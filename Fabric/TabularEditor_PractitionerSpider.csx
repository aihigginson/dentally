// TabularEditor_PractitionerSpider.csx
// Creates 7 raw-value axis measures for the Practitioner Spider (Deneb radar) visual.
// Normalisation to 0-1 per axis is done inside the Vega spec so the best practitioner
// on each axis always reaches the outer ring; tooltips show actual values.
//
// PBI visual setup:
//   1. Add a Deneb visual to Home page 3.
//   2. Fields: List Practitioners[Practitioner Name] + all 7 Spider * measures.
//   3. Paste Deneb_PractitionerSpider.json as the Vega spec.
//
// History:
//   *01  21/05/2026  AIH  Initial

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

// Axis 1 — Revenue as % of target (higher = better)
add("Spider Revenue vs Target",
    @"VAR actual = [Total Revenue]
VAR target = [Total Revenue Target]
RETURN DIVIDE(actual, target)",
    @"0.0%");

// Axis 2 — Chair utilisation (higher = better)
add("Spider Chair Utilisation",
    @"[Chair Utilisation]",
    @"0.0%");

// Axis 3 — Revenue per clinical hour (higher = better, raw £ normalised in Vega)
add("Spider Rev Per Hour",
    @"[Revenue Per Clinical Hour]",
    @"£#,##0");

// Axis 4 — New patients seen (higher = better, raw count normalised in Vega)
add("Spider New Patients",
    @"[New Patients]",
    @"#,##0");

// Axis 5 — Treatment plan conversion (higher = better)
add("Spider Tx Conversion",
    @"[Treatment Acceptance Rate]",
    @"0.0%");

// Axis 6 — DNA rate inverted (higher = better, so 1 - DNA Rate)
add("Spider DNA Score",
    @"VAR r = [DNA Rate]
RETURN IF(ISBLANK(r), BLANK(), 1 - r)",
    @"0.0%");

// Axis 7 — UDA completion rate (higher = better; BLANK for private-only practitioners)
add("Spider UDA Completion",
    @"IFERROR([NHS UDA Completion Rate], BLANK())",
    @"0.0%");
