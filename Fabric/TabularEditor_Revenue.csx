// Revenue KPI measures — data-driven generation.
//
// Each KPI card needs three derived measures: a Target, a "vs Target" variance
// label, and a BG colour. These were ~40 near-identical lines per KPI; they're
// now generated from per-KPI specs via the builder functions below. The DAX is
// functionally identical to the previous hand-written version (DAX ignores
// whitespace). Value measures stay bespoke (each has unique logic).
//
// NOTE: Tabular Editor's C# does NOT support string interpolation (dollar-prefixed
// strings), so templates are verbatim strings with {b}/{key} placeholders filled
// by .Replace().

var t = Model.Tables["_Measures"];
var g = "Revenue KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Target DAX builders (target model: Fact_Daily_Targets + Target_Level resolution + FTE) ──
// lvl: a practitioner in context -> their Custom Role; a role selected -> that role; else Practice.
// The *FTE builders scale the per-FTE role target by SUM(FTE) of the practitioners in context;
// at Practice level the entered whole-practice number is used as-is (fte = 1).
Func<string,string> band = key => (@"CALCULATE(
    MAX('_Daily Targets'[Variance]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)").Replace("{key}", key);

Func<string,string> tCum = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
RETURN IF(ISBLANK(base_t), BLANK(), base_t)").Replace("{key}", key);

Func<string,string> tCumFTE = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR fte = IF(lvl = ""Practice"", 1, SUM('List Practitioners'[FTE]))
RETURN IF(ISBLANK(base_t), BLANK(), base_t * fte)").Replace("{key}", key);

Func<string,string> tRate = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
RETURN CALCULATE(
    MAX('_Daily Targets'[Annual Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)").Replace("{key}", key);

Func<string,string> tRateFTE = key => (@"VAR lvl = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR base_t = CALCULATE(
    MAX('_Daily Targets'[Annual Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric] = ""{key}"", '_Daily Targets'[Target Level] = lvl)
VAR fte = IF(lvl = ""Practice"", 1, SUM('List Practitioners'[FTE]))
RETURN IF(ISBLANK(base_t), BLANK(), base_t * fte)").Replace("{key}", key);

Func<string,string> tRate100 = key => tRate(key) + " / 100";

// ── vs-Target DAX builders ───────────────────────────────────────────────────
Func<string,string> vPct = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPctGrey = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(actual), ""No data"",
    IF(ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%"")))").Replace("{b}", b);

Func<string,string> vPp = b => (@"VAR actual  = [{b}]
VAR target  = [{b} Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))").Replace("{b}", b);

// ── BG colour DAX builders (band from _Daily Targets[Variance] at the resolved level) ──
Func<string,string,string> bgHigherRefF = (b, key) => (@"VAR actual = [{b}]
VAR lvl    = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target = [{b} Target]
VAR band   = {band}
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")").Replace("{band}", band(key)).Replace("{b}", b).Replace("{key}", key);

// In the new model target+band both come from the fact, so higher=better Ref and Eff are identical.
Func<string,string,string> bgHigherEffF = bgHigherRefF;

// lower=better; grey=true adds the blank-actual grey row (e.g. Outstanding Invoices)
Func<string,string,bool,string> bgLowerEffF = (b, key, grey) => {
    var greyRow = grey ? @"ISBLANK(actual), ""#E0E0E0"",
    " : "";
    return (@"VAR actual = [{b}]
VAR lvl    = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target = [{b} Target]
VAR band   = {band}
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    {grey}ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")").Replace("{band}", band(key)).Replace("{b}", b).Replace("{key}", key).Replace("{grey}", greyRow);
};

Func<string,string,string> bgHigherPpF = (b, key) => (@"VAR actual = [{b}]
VAR lvl     = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target  = [{b} Target]
VAR band    = {band}
VAR diff_pp = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")").Replace("{band}", band(key)).Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerPpF = (b, key) => (@"VAR actual = [{b}]
VAR lvl     = COALESCE(SELECTEDVALUE('List Practitioners'[Custom Role]), ""Practice"")
VAR target  = [{b} Target]
VAR band    = {band}
VAR diff_pp = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp <= -band, ""#1a7f3c"",
    diff_pp <= 0,     ""#6abf7b"",
    diff_pp <= band,  ""#f4a261"",
                      ""#c0392b"")").Replace("{band}", band(key)).Replace("{b}", b).Replace("{key}", key);

// Emits the three derived measures for a KPI from pre-built DAX.
Action<string,string,string,string,string> kpi = (baseName, fmt, targetDax, vsDax, bgDax) => {
    add(baseName + " Target",    targetDax, fmt);
    add(baseName + " vs Target", vsDax,     "");
    add(baseName + " BG",        bgDax,     "");
};

// ── Value measures (bespoke) ─────────────────────────────────────────────────

add("Total Revenue",
    @"SUM('_Invoice Items'[Total Price])",
    "£#,##0");

add("NHS Revenue",
    @"CALCULATE(
    SUM('_Invoice Items'[Total Price]),
    '_Invoice Items'[NHS Charge] > 0)",
    "£#,##0");

add("Private Revenue",
    @"CALCULATE(
    SUM('_Invoice Items'[Total Price]),
    '_Invoice Items'[NHS Charge] = 0)",
    "£#,##0");

add("Outstanding Invoices",
    @"VAR snap_fk =
    MAXX(
        FILTER( ALLSELECTED( '_KPI Snapshot' ), '_KPI Snapshot'[Snapshot Grain] = ""weekly"" ),
        '_KPI Snapshot'[fk Date]
    )
RETURN
CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[fk Date]        = snap_fk,
    '_KPI Snapshot'[Metric]         = ""outstanding_invoices"",
    '_KPI Snapshot'[Snapshot Grain] = ""weekly""
)",
    "£#,##0");

add("Revenue Per Patient",
    @"DIVIDE([Total Revenue], [Active Patients])",
    "£#,##0");

add("Revenue Per Clinical Hour",
    @"VAR by_prac_day =
SUMMARIZE(
    FILTER(
        'Aggregate Site Patient Practitioner Daily',
        RELATED('List Practitioners'[Role]) IN {""dentist"",""hygienist"",""orthodontist"",""specialist"",""therapist""}
    ),
    'Aggregate Site Patient Practitioner Daily'[fk Practitioner],
    'Aggregate Site Patient Practitioner Daily'[fk Date],
    ""WH"", MAX('Aggregate Site Patient Practitioner Daily'[Worked Hours]))
VAR total_worked = SUMX(by_prac_day, [WH])
RETURN DIVIDE([Total Revenue], total_worked)",
    "£#,##0");

add("DNA Revenue Lost",
    @"VAR dna_count =
    CALCULATE(
        SUM('Aggregate Site Patient Practitioner Daily'[DNA Appointments]),
        REMOVEFILTERS('List Practitioners')
    )
VAR avg_appt_value =
    DIVIDE(
        CALCULATE([Total Revenue],
            REMOVEFILTERS('List Date'),
            REMOVEFILTERS('List Practitioners')),
        CALCULATE(
            SUM('Aggregate Site Patient Practitioner Daily'[Appointments]),
            REMOVEFILTERS('List Date'),
            REMOVEFILTERS('List Practitioners'))
    )
RETURN dna_count * avg_appt_value",
    "£#,##0");

add("Deposit Value",
    @"DIVIDE(SUM('_Payments'[Deposit Amount]), [Total Revenue])",
    "0.0%");

// Invoice grain split: per-invoice discount (header Amount - sum of its line Total Price,
// when positive) is precomputed as Fact_Invoices.Discount_Amount, so this is a simple ratio.
add("Discounts",
    @"DIVIDE(SUM('_Invoices'[Discount Amount]), [Total Revenue])",
    "0.0%");

// ── Derived Target / vs-Target / BG per KPI (data-driven) ─────────────────────

kpi("Total Revenue",             "£#,##0", tCumFTE("total_revenue"),            vPct("Total Revenue"),             bgHigherRefF("Total Revenue", "total_revenue"));
kpi("NHS Revenue",               "£#,##0", tCumFTE("nhs_revenue"),              vPct("NHS Revenue"),               bgHigherRefF("NHS Revenue", "nhs_revenue"));
kpi("Private Revenue",           "£#,##0", tCumFTE("private_revenue"),          vPct("Private Revenue"),           bgHigherRefF("Private Revenue", "private_revenue"));
kpi("Outstanding Invoices",      "£#,##0", tRate("outstanding_invoices"),    vPctGrey("Outstanding Invoices"),  bgLowerEffF("Outstanding Invoices", "outstanding_invoices", true));
kpi("Revenue Per Patient",       "£#,##0", tRate("revenue_per_patient"),        vPct("Revenue Per Patient"),       bgHigherEffF("Revenue Per Patient", "revenue_per_patient"));
kpi("Revenue Per Clinical Hour", "£#,##0", tRate("revenue_per_clinical_hour"),  vPct("Revenue Per Clinical Hour"), bgHigherEffF("Revenue Per Clinical Hour", "revenue_per_clinical_hour"));
kpi("DNA Revenue Lost",          "£#,##0", tRate("dna_revenue_lost"),           vPct("DNA Revenue Lost"),          bgLowerEffF("DNA Revenue Lost", "dna_revenue_lost", false));
kpi("Deposit Value",             "0.0%",   tRate100("deposit_ratio"),           vPp("Deposit Value"),              bgHigherPpF("Deposit Value", "deposit_ratio"));
kpi("Discounts",                 "0.0%",   tRate100("discounts"),               vPp("Discounts"),                  bgLowerPpF("Discounts", "discounts"));

Info("Revenue KPI measures created (data-driven).");
