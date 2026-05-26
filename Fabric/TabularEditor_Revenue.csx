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

// Supports_Practitioner = 0 — always show site total; bypass practitioner slicer
add("Outstanding Invoices",
    @"VAR snap_fk =
    CALCULATE(
        MAXX(
            FILTER( ALLSELECTED( '_KPI Snapshot' ), '_KPI Snapshot'[Snapshot Grain] = ""weekly"" ),
            '_KPI Snapshot'[fk Date]
        ),
        REMOVEFILTERS( 'List Practitioners' )
    )
RETURN
CALCULATE(
    SUM( '_KPI Snapshot'[Value] ),
    '_KPI Snapshot'[fk Date]        = snap_fk,
    '_KPI Snapshot'[Metric]         = ""outstanding_invoices"",
    '_KPI Snapshot'[Snapshot Grain] = ""weekly"",
    REMOVEFILTERS( 'List Practitioners' )
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
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))",
    "£#,##0");

add("Outstanding Invoices vs Target",
    @"VAR actual = [Outstanding Invoices]
VAR target = [Outstanding Invoices Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(actual), ""No data"",
    IF(ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%"")))",
    "");

add("Revenue Per Patient Target",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))",
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
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_clinical_hour"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_clinical_hour"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))",
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
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_dentist_hour"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_dentist_hour"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))",
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
    @"VAR actual   = [Total Revenue]
VAR target   = [Total Revenue Target]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""total_revenue"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""total_revenue"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

add("NHS Revenue BG",
    @"VAR actual   = [NHS Revenue]
VAR target   = [NHS Revenue Target]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_revenue"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""nhs_revenue"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Private Revenue BG",
    @"VAR actual   = [Private Revenue]
VAR target   = [Private Revenue Target]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""private_revenue"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""private_revenue"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
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
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""outstanding_invoices"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual),  ""#E0E0E0"",
    ISBLANK(target),  ""#FFFFFF"",
    pct <= -band,     ""#1a7f3c"",
    pct <= 0,         ""#6abf7b"",
    pct <= band,      ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Revenue Per Patient BG",
    @"VAR actual   = [Revenue Per Patient]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_patient"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
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
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_clinical_hour"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_clinical_hour"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_clinical_hour"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_clinical_hour"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
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
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_dentist_hour"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_dentist_hour"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_dentist_hour"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""revenue_per_dentist_hour"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    pct >= band,      ""#1a7f3c"",
    pct >= 0,         ""#6abf7b"",
    pct >= -band,     ""#f4a261"",
                      ""#c0392b"")",
    "");

// ── Home page measures ────────────────────────────────────────────────────────

// DNA Revenue Lost: Supports_Practitioner = 0 — always use site-total DNA count and avg value.
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
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""deposit_value"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""deposit_value"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))",
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
    @"VAR actual   = [Deposit Value]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""deposit_value"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""deposit_value"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""deposit_value"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""deposit_value"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Discounts Target",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""discounts"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""discounts"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))",
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
    @"VAR actual   = [Discounts]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""discounts"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""discounts"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""discounts"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""discounts"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")",
    "");

add("DNA Revenue Lost Target",
    @"VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
RETURN COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))",
    "£#,##0");

add("DNA Revenue Lost vs Target",
    @"VAR actual = [DNA Revenue Lost]
VAR target = [DNA Revenue Lost Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("DNA Revenue Lost BG",
    @"VAR actual   = [DNA Revenue Lost]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR target   = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Target Value]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Target Value]))
VAR band     = COALESCE(
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost"" && '_Targets'[fk Practice Site] = sel_site && sel_site <> -1), '_Targets'[Variance]),
    MAXX(FILTER('_Targets', '_Targets'[Metric] = ""dna_revenue_lost"" && '_Targets'[fk Practice Site] = -1), '_Targets'[Variance]))
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")",
    "");

Info("Revenue KPI measures created.");
