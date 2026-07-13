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

// ── Target DAX builders ──────────────────────────────────────────────────────
Func<string,string> tDaily = key => (@"VAR sel_site    = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac    = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR run_rate    = [_Period Run Rate]
VAR full_target = CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    TREATAS(VALUES('List Date'[pk Date]), '_Daily Targets'[fk Date]),
    '_Daily Targets'[Metric]           = ""{key}"",
    '_Daily Targets'[fk Practice Site] = sel_site,
    '_Daily Targets'[fk Practitioner]  = sel_prac)
RETURN IF(ISBLANK(full_target), BLANK(), full_target * run_rate)").Replace("{key}", key);

Func<string,string> tEff = key => (@"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]      = ""{key}"",
    '_Effective Targets'[Period Value] = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)").Replace("{key}", key);

Func<string,string> tEff100 = key => tEff(key) + " / 100";

// tEffAdd: like tEff but also filters fk Practitioner -- for ADDITIVE (count/currency) metrics
// whose target must follow the actual's real grain (blank at a site/practitioner with no entered
// target). Rate metrics keep tEff (site-only, with the practice fallback).
Func<string,string> tEffAdd = key => (@"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac   = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""{key}"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site,
    '_Effective Targets'[fk Practitioner]  = sel_prac)").Replace("{key}", key);

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

// ── BG colour DAX builders ───────────────────────────────────────────────────
// higher=better, target via the [base Target] measure, band inline from _Effective
Func<string,string,string> bgHigherRefF = (b, key) => (@"VAR actual   = [{b}]
VAR target   = [{b} Target]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

// higher=better, target+band both inline from _Effective
Func<string,string,string> bgHigherEffF = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

// lower=better; grey=true adds the blank-actual grey row (e.g. Outstanding Invoices)
Func<string,string,bool,string> bgLowerEffF = (b, key, grey) => {
    var greyRow = grey ? @"ISBLANK(actual), ""#E0E0E0"",
    " : "";
    return (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    {grey}ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key).Replace("{grey}", greyRow);
};

// pp-based ratio metrics (target from _Effective / 100)
Func<string,string,string> bgHigherPpF = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerPpF = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp <= -band, ""#1a7f3c"",
    diff_pp <= 0,     ""#6abf7b"",
    diff_pp <= band,  ""#f4a261"",
                      ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

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

kpi("Total Revenue",             "£#,##0", tDaily("total_revenue"),            vPct("Total Revenue"),             bgHigherRefF("Total Revenue", "total_revenue"));
kpi("NHS Revenue",               "£#,##0", tDaily("nhs_revenue"),              vPct("NHS Revenue"),               bgHigherRefF("NHS Revenue", "nhs_revenue"));
kpi("Private Revenue",           "£#,##0", tDaily("private_revenue"),          vPct("Private Revenue"),           bgHigherRefF("Private Revenue", "private_revenue"));
kpi("Outstanding Invoices",      "£#,##0", tEffAdd("outstanding_invoices"),    vPctGrey("Outstanding Invoices"),  bgLowerEffF("Outstanding Invoices", "outstanding_invoices", true));
kpi("Revenue Per Patient",       "£#,##0", tEff("revenue_per_patient"),        vPct("Revenue Per Patient"),       bgHigherEffF("Revenue Per Patient", "revenue_per_patient"));
kpi("Revenue Per Clinical Hour", "£#,##0", tEff("revenue_per_clinical_hour"),  vPct("Revenue Per Clinical Hour"), bgHigherEffF("Revenue Per Clinical Hour", "revenue_per_clinical_hour"));
kpi("Revenue Per Dentist Hour",  "£#,##0", tEff("revenue_per_dentist_hour"),   vPct("Revenue Per Dentist Hour"),  bgHigherEffF("Revenue Per Dentist Hour", "revenue_per_dentist_hour"));
kpi("DNA Revenue Lost",          "£#,##0", tEff("dna_revenue_lost"),           vPct("DNA Revenue Lost"),          bgLowerEffF("DNA Revenue Lost", "dna_revenue_lost", false));
kpi("Deposit Value",             "0.0%",   tEff100("deposit_ratio"),           vPp("Deposit Value"),              bgHigherPpF("Deposit Value", "deposit_ratio"));
kpi("Discounts",                 "0.0%",   tEff100("discounts"),               vPp("Discounts"),                  bgLowerPpF("Discounts", "discounts"));

Info("Revenue KPI measures created (data-driven).");
