// Patient KPI measures — data-driven generation.
//
// Per-KPI Target / vs-Target / BG blocks (~40 lines each) are generated from
// per-KPI specs via the builder functions below. DAX is functionally identical to
// the previous hand-written version (DAX ignores whitespace). Value measures stay
// bespoke. All targets come from '_Effective Targets'.
//
// NOTE: Tabular Editor's C# has no string interpolation (dollar-prefixed strings),
// so templates are verbatim @"..." with {b}/{key} placeholders filled via .Replace().
//
// Builder variants on this page (named explicitly so each is a faithful copy):
//   Target : tEff (plain) | tEffRunRate (count metrics x run rate) | tEff100 (ratios, /100)
//   vs     : vPct | vPctP (+prefix) | vPctGreyP (+No-data +prefix)
//            vPp  | vPpP  (+prefix)  | vPpGreyP  (+No-data +prefix)
//   BG     : bgHigherEff | bgHigherEffGrey | bgLowerEffGrey
//            bgHigherPp   | bgHigherPpGrey  | bgLowerPp
// ("prefix" = the "⚠ " shown when a practitioner slicer is active on a
//  Supports_Practitioner = 0 metric.)

var t = Model.Tables["_Measures"];
var g = "Patients KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Target builders ──────────────────────────────────────────────────────────
Func<string,string> tEff = key => (@"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
RETURN CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""{key}"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)").Replace("{key}", key);

Func<string,string> tEffRunRate = key => (@"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key     = [_Target FY Key]
VAR full_target = CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""{key}"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site)
RETURN IF(ISBLANK(full_target), BLANK(), full_target * [_Period Run Rate])").Replace("{key}", key);

Func<string,string> tEff100 = key => tEff(key) + " / 100";

// tEffAdd / tEffRunRateAdd: like tEff / tEffRunRate but also filter fk Practitioner -- for
// ADDITIVE metrics whose target follows the actual's real grain (blank where no entered target).
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

Func<string,string> tEffRunRateAdd = key => (@"VAR sel_site   = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR sel_prac   = SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)
VAR fy_key     = [_Target FY Key]
VAR full_target = CALCULATE(
    MAX('_Effective Targets'[Effective Target]),
    TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]),
    '_Effective Targets'[Metric]           = ""{key}"",
    '_Effective Targets'[Period Value]     = fy_key,
    '_Effective Targets'[fk Practice Site] = sel_site,
    '_Effective Targets'[fk Practitioner]  = sel_prac)
RETURN IF(ISBLANK(full_target), BLANK(), full_target * [_Period Run Rate])").Replace("{key}", key);

// ── vs-Target builders ───────────────────────────────────────────────────────
Func<string,string> vPct = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPctP = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))").Replace("{b}", b);

Func<string,string> vPctGreyP = b => (@"VAR actual = [{b}]
VAR target = [{b} Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
VAR prefix = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(actual), ""No data"",
    IF(ISBLANK(target), BLANK(),
    prefix & IF(pct >= 0,
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

Func<string,string> vPpP = b => (@"VAR actual  = [{b}]
VAR target  = [{b} Target]
VAR diff_pp = (actual - target) * 100
VAR prefix  = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(target), BLANK(),
    prefix & IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))").Replace("{b}", b);

Func<string,string> vPpGreyP = b => (@"VAR actual  = [{b}]
VAR target  = [{b} Target]
VAR diff_pp = (actual - target) * 100
VAR prefix  = IF([_Is Practitioner Filtered] = 1, ""⚠ "", """")
RETURN IF(
    ISBLANK(actual), ""No data"",
    IF(ISBLANK(target), BLANK(),
    prefix & IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp"")))").Replace("{b}", b);

// ── BG builders (target+band inline from _Effective) ─────────────────────────
Func<string,string,string> bgHigherEff = (b, key) => (@"VAR actual   = [{b}]
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

Func<string,string,string> bgHigherEffGrey = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual), ""#E0E0E0"",
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerEffGrey = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
VAR pct      = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual), ""#E0E0E0"",
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgHigherPp = (b, key) => (@"VAR actual   = [{b}]
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

Func<string,string,string> bgHigherPpGrey = (b, key) => (@"VAR actual   = [{b}]
VAR sel_site = SELECTEDVALUE('List Practice Sites'[pk Practice Site], -1)
VAR fy_key   = [_Target FY Key]
VAR target   = [{b} Target]
VAR band     = CALCULATE(MAX('_Effective Targets'[Effective Variance]), TREATAS(VALUES('List Practice Sites'[Tenant ID]), '_Effective Targets'[Tenant ID]), '_Effective Targets'[Metric] = ""{key}"", '_Effective Targets'[Period Value] = fy_key, '_Effective Targets'[fk Practice Site] = sel_site, '_Effective Targets'[fk Practitioner] = -1)
VAR diff_pp  = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(actual),  ""#E0E0E0"",
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")").Replace("{b}", b).Replace("{key}", key);

Func<string,string,string> bgLowerPp = (b, key) => (@"VAR actual   = [{b}]
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

Action<string,string,string,string,string> kpi = (baseName, fmt, targetDax, vsDax, bgDax) => {
    add(baseName + " Target",    targetDax, fmt);
    add(baseName + " vs Target", vsDax,     "");
    add(baseName + " BG",        bgDax,     "");
};

// ── Value measures (bespoke) ─────────────────────────────────────────────────

add("New Patients",
    @"CALCULATE(
    DISTINCTCOUNT('Aggregate Site Patient Practitioner Daily'[fk Patient]),
    'Aggregate Site Patient Practitioner Daily'[New Patient] = TRUE())",
    "#,##0");

add("Lapsed Patients",
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
    '_KPI Snapshot'[Metric]         = ""lapsed_patients"",
    '_KPI Snapshot'[Snapshot Grain] = ""weekly"",
    REMOVEFILTERS( 'List Practitioners' )
)",
    "#,##0");

add("Net Patient Growth",
    @"VAR period_start = MIN('List Date'[Full Date])
VAR period_end   = MAX('List Date'[Full Date])
VAR lapsed_flow  =
    COUNTROWS(
        FILTER(
            ALL('List Patients'),
            NOT ISBLANK('List Patients'[Last Exam Date])
            && EDATE('List Patients'[Last Exam Date], 24) >= period_start
            && EDATE('List Patients'[Last Exam Date], 24) <= period_end
            && NOT ISBLANK('List Patients'[First Appointment Date])
            && 'List Patients'[First Appointment Date] < period_start
        )
    )
RETURN [New Patients] - lapsed_flow",
    "#,##0");

add("Retention Outlook",
    @"VAR due =
    CALCULATE(
        DISTINCTCOUNT( '_Recalls'[fk Patient] ),
        '_Recalls'[Is In Scope] = TRUE(),
        REMOVEFILTERS( 'List Date' )
    )
VAR booked =
    CALCULATE(
        DISTINCTCOUNT( '_Recalls'[fk Patient] ),
        '_Recalls'[Is In Scope] = TRUE(),
        '_Recalls'[Is Booked]   = TRUE(),
        REMOVEFILTERS( 'List Date' )
    )
RETURN DIVIDE( booked, due )",
    "#,##0.0%");

add("Active Patients",
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
    '_KPI Snapshot'[Metric]         = ""active_patients"",
    '_KPI Snapshot'[Snapshot Grain] = ""weekly"",
    REMOVEFILTERS( 'List Practitioners' )
)",
    "#,##0");

add("Recall Effectiveness",
    @"VAR in_scope =
    CALCULATE(
        COUNTROWS( '_Recalls' ),
        '_Recalls'[Is In Scope] = TRUE(),
        REMOVEFILTERS( 'List Date' )
    )
VAR contacted =
    CALCULATE(
        COUNTROWS( '_Recalls' ),
        '_Recalls'[Is In Scope]      = TRUE(),
        '_Recalls'[Is Reminder Sent] = TRUE(),
        REMOVEFILTERS( 'List Date' )
    )
RETURN DIVIDE( contacted, in_scope )",
    "#,##0.0%");

add("Patient Retention",
    @"DIVIDE(
    COUNTROWS(FILTER('Aggregate Site Patient Current',
        'Aggregate Site Patient Current'[Retained Patients] = TRUE())),
    COUNTROWS(FILTER('Aggregate Site Patient Current',
        'Aggregate Site Patient Current'[Active Patients] = TRUE())))",
    "#,##0.0%");

add("Recalls Overdue Not Sent",
    @"DIVIDE(
    COUNTROWS(FILTER('Aggregate Site Patient Current',
        'Aggregate Site Patient Current'[Recall Due]  = TRUE()
        && 'Aggregate Site Patient Current'[Recall Sent] = FALSE())),
    COUNTROWS(FILTER('Aggregate Site Patient Current',
        'Aggregate Site Patient Current'[Recall Due] = TRUE())))",
    "#,##0.0%");

add("Overdue Recalls",
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
    '_KPI Snapshot'[Metric]         = ""overdue_recalls"",
    '_KPI Snapshot'[Snapshot Grain] = ""weekly"",
    REMOVEFILTERS( 'List Practitioners' )
)",
    "#,##0");

add("Email Details Rate",
    @"DIVIDE(
    CALCULATE(
        SUM('List Patients'[Patient Count]),
        NOT ISBLANK('List Patients'[Email Address])),
    SUM('List Patients'[Patient Count]))",
    "#,##0.0%");

add("Phone Details Rate",
    @"DIVIDE(
    CALCULATE(
        SUM('List Patients'[Patient Count]),
        NOT ISBLANK('List Patients'[Mobile Phone])
        || NOT ISBLANK('List Patients'[Home Phone])),
    SUM('List Patients'[Patient Count]))",
    "#,##0.0%");

// ── Derived Target / vs-Target / BG per KPI (data-driven) ─────────────────────

kpi("New Patients",             "#,##0",    tEffRunRateAdd("new_patients"),         vPct("New Patients"),               bgHigherEff("New Patients", "new_patients"));
kpi("Net Patient Growth",       "#,##0",    tEffRunRate("net_patient_growth"),   vPctP("Net Patient Growth"),        bgHigherEff("Net Patient Growth", "net_patient_growth"));
kpi("Lapsed Patients",          "#,##0",    tEffAdd("lapsed_patients"),             vPctGreyP("Lapsed Patients"),       bgLowerEffGrey("Lapsed Patients", "lapsed_patients"));
kpi("Active Patients",          "#,##0",    tEffAdd("active_patients"),             vPctGreyP("Active Patients"),       bgHigherEffGrey("Active Patients", "active_patients"));
kpi("Recall Effectiveness",     "#,##0.0%", tEff100("recall_compliance"),        vPp("Recall Effectiveness"),        bgHigherPp("Recall Effectiveness", "recall_compliance"));
kpi("Patient Retention",        "#,##0.0%", tEff100("patient_retention"),        vPpP("Patient Retention"),          bgHigherPp("Patient Retention", "patient_retention"));
kpi("Recalls Overdue Not Sent", "#,##0.0%", tEff100("recalls_overdue_not_sent"), vPpP("Recalls Overdue Not Sent"),   bgLowerPp("Recalls Overdue Not Sent", "recalls_overdue_not_sent"));
kpi("Retention Outlook",        "#,##0.0%", tEff100("retention_outlook"),        vPpGreyP("Retention Outlook"),      bgHigherPpGrey("Retention Outlook", "retention_outlook"));
kpi("Overdue Recalls",          "#,##0",    tEffAdd("overdue_recalls"),             vPctGreyP("Overdue Recalls"),       bgLowerEffGrey("Overdue Recalls", "overdue_recalls"));
kpi("Email Details Rate",       "#,##0.0%", tEff100("email_details_rate"),       vPpP("Email Details Rate"),         bgHigherPp("Email Details Rate", "email_details_rate"));
kpi("Phone Details Rate",       "#,##0.0%", tEff100("phone_details_rate"),       vPpP("Phone Details Rate"),         bgHigherPp("Phone Details Rate", "phone_details_rate"));

Info("Patients KPI measures created (data-driven).");
