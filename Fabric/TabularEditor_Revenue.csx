var t = Model.Tables["_Measures"];
var g = "Revenue KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Value measures ───────────────────────────────────────────────────────────
// Revenue source: _Invoice Items[Total Price] (item-level price x qty)
// NHS split:      NHS Charge > 0 flags NHS items (stored as 0.00 / 1.00 in Gold)
// Outstanding:    Invoice Amount Outstanding is invoice-level — deduplicate by Invoice ID
// Note: Total Deposits / Deposit Ratio removed — no item-type column in the schema

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
    @"SUMX(
    SUMMARIZE('_Invoice Items',
        '_Invoice Items'[Invoice ID],
        ""_oa"", MAX('_Invoice Items'[Invoice Amount Outstanding])),
    [_oa])",
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

add("Revenue Per Dentist Hour",
    @"VAR by_prac_day =
SUMMARIZE(
    FILTER(
        'Aggregate Site Patient Practitioner Daily',
        RELATED('List Practitioners'[Role]) IN {""dentist"",""orthodontist""}
    ),
    'Aggregate Site Patient Practitioner Daily'[fk Practitioner],
    'Aggregate Site Patient Practitioner Daily'[fk Date],
    ""WH"", MAX('Aggregate Site Patient Practitioner Daily'[Worked Hours]))
VAR total_worked = SUMX(by_prac_day, [WH])
RETURN DIVIDE([Total Revenue], total_worked)",
    "£#,##0");

// ── Target and variance measures ─────────────────────────────────────────────
// cumulative metrics (total_revenue, nhs_revenue, private_revenue):
//   annual target is exploded into working-day rows in Gold.Fact_Daily_Targets.
//   SUM over the active date filter gives the correct prorated target automatically.
//   No _Period Run Rate proration needed.
// rate / point_in_time metrics: fixed threshold from _Targets as before.

add("Total Revenue Target",
    @"CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    '_Daily Targets'[Metric] = ""total_revenue"")",
    "£#,##0");

add("Total Revenue vs Target",
    @"VAR actual = [Total Revenue]
VAR target = [Total Revenue Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("NHS Revenue Target",
    @"CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    '_Daily Targets'[Metric] = ""nhs_revenue"")",
    "£#,##0");

add("NHS Revenue vs Target",
    @"VAR actual = [NHS Revenue]
VAR target = [NHS Revenue Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Private Revenue Target",
    @"CALCULATE(
    SUM('_Daily Targets'[Daily Target Value]),
    '_Daily Targets'[Metric] = ""private_revenue"")",
    "£#,##0");

add("Private Revenue vs Target",
    @"VAR actual = [Private Revenue]
VAR target = [Private Revenue Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Outstanding Invoices Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices""),
    '_Targets'[Target Value])",
    "£#,##0");

add("Outstanding Invoices vs Target",
    @"VAR actual = [Outstanding Invoices]
VAR target = [Outstanding Invoices Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Revenue Per Patient Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient""),
    '_Targets'[Target Value])",
    "£#,##0");

add("Revenue Per Patient vs Target",
    @"VAR actual = [Revenue Per Patient]
VAR target = [Revenue Per Patient Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Revenue Per Clinical Hour Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_clinical_hour""),
    '_Targets'[Target Value])",
    "£#,##0");

add("Revenue Per Clinical Hour vs Target",
    @"VAR actual = [Revenue Per Clinical Hour]
VAR target = [Revenue Per Clinical Hour Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Revenue Per Dentist Hour Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_dentist_hour""),
    '_Targets'[Target Value])",
    "£#,##0");

add("Revenue Per Dentist Hour vs Target",
    @"VAR actual = [Revenue Per Dentist Hour]
VAR target = [Revenue Per Dentist Hour Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

// ── BG colour measures ───────────────────────────────────────────────────────
// currency/count metrics → relative %  (pct = (actual-target)/|target| * 100)
// above range: pct >= band = strong green … pct < -band = strong red

add("Total Revenue BG",
    @"VAR actual = [Total Revenue]
VAR target = [Total Revenue Target]
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""total_revenue""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

add("NHS Revenue BG",
    @"VAR actual = [NHS Revenue]
VAR target = [NHS Revenue Target]
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_revenue""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Private Revenue BG",
    @"VAR actual = [Private Revenue]
VAR target = [Private Revenue Target]
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""private_revenue""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Outstanding Invoices BG",
    @"VAR actual   = [Outstanding Invoices]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices""), '_Targets'[Target Value])
VAR band     = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Revenue Per Patient BG",
    @"VAR actual   = [Revenue Per Patient]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient""), '_Targets'[Target Value])
VAR band     = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Revenue Per Clinical Hour BG",
    @"VAR actual   = [Revenue Per Clinical Hour]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_clinical_hour""), '_Targets'[Target Value])
VAR band     = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_clinical_hour""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Revenue Per Dentist Hour BG",
    @"VAR actual   = [Revenue Per Dentist Hour]
VAR target   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_dentist_hour""), '_Targets'[Target Value])
VAR band     = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_dentist_hour""), '_Targets'[Variance])
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

// ── Home page measures ────────────────────────────────────────────────────────

// DNA Revenue Lost: DNA appointments in the selected period × all-time avg revenue per appointment.
// All-time average used as the rate — more stable than the period average on short windows.
add("DNA Revenue Lost",
    @"VAR dna_count =
    SUM('Aggregate Site Patient Practitioner Daily'[DNA Appointments])
VAR avg_appt_value =
    DIVIDE(
        CALCULATE([Total Revenue],    REMOVEFILTERS('List Date')),
        CALCULATE(SUM('Aggregate Site Patient Practitioner Daily'[Appointments]), REMOVEFILTERS('List Date'))
    )
RETURN dna_count * avg_appt_value",
    "£#,##0");

add("Deposit Value",
    @"SUM('_Payments'[Deposit Amount])",
    "£#,##0");

add("Discounts",
    @"SUMX(
    SUMMARIZE('_Invoice Items',
        '_Invoice Items'[Invoice ID],
        ""_inv"",   MAX('_Invoice Items'[Invoice Amount]),
        ""_items"", SUM('_Invoice Items'[Total Price])),
    IF([_inv] > [_items], [_inv] - [_items], 0))",
    "£#,##0");

add("Deposit Value Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""deposit_value""),
    '_Targets'[Target Value])",
    "£#,##0");

add("Deposit Value vs Target",
    @"VAR actual = [Deposit Value]
VAR target = [Deposit Value Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Deposit Value BG",
    @"VAR actual = [Deposit Value]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""deposit_value""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""deposit_value""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Discounts Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""discounts""),
    '_Targets'[Target Value])",
    "£#,##0");

add("Discounts vs Target",
    @"VAR actual = [Discounts]
VAR target = [Discounts Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Discounts BG",
    @"VAR actual = [Discounts]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""discounts""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""discounts""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")",
    "");

add("DNA Revenue Lost Target",
    @"MAXX(
    FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost""),
    '_Targets'[Target Value])",
    "£#,##0");

add("DNA Revenue Lost vs Target",
    @"VAR actual = [DNA Revenue Lost]
VAR target = [DNA Revenue Lost Target]
VAR pct    = DIVIDE(target - actual, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("DNA Revenue Lost BG",
    @"VAR actual = [DNA Revenue Lost]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")",
    "");

Info("Revenue KPI measures created.");
