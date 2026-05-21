var t = Model.Tables["_Measures"];
var g = "Home Detail KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Revenue ───────────────────────────────────────────────────────────────────

// Average private treatment value per plan that has been started
add("Average Plan Value",
    @"DIVIDE(
    SUM('List Treatment Plans'[Private Treatment Value]),
    CALCULATE(
        COUNTROWS('List Treatment Plans'),
        NOT ISBLANK('List Treatment Plans'[Start Date])))",
    "£#,##0");

// Deposit Value: no item-type column in schema to identify deposits
add("Deposit Value",
    @"0",
    "£#,##0");

// Discounts: no discount column in invoice items schema
add("Discounts",
    @"0",
    "£#,##0");

// ── Scheduling ────────────────────────────────────────────────────────────────

add("Cancellation Frequency",
    @"CALCULATE(
    COUNTROWS('_Appointments'),
    '_Appointments'[Is Cancelled] = TRUE())",
    "#,##0");

// Short Notice Cancellation Rate: requires List Cancellation Reasons with an
// Is_Short_Notice flag — no cancellation reasons dim in Gold yet.
add("Short Notice Cancellation Rate",
    @"0",
    "#,##0.0%");

// ── Patients ──────────────────────────────────────────────────────────────────

// Overdue Recalls: in-scope recalls (due and/or reminded) with no booking.
// REMOVEFILTERS('List Date') so the count is always current, not filtered to slicer period.
add("Overdue Recalls",
    @"CALCULATE(
    COUNTROWS('_Recalls'),
    '_Recalls'[Is In Scope] = TRUE(),
    '_Recalls'[Is Booked]   = FALSE(),
    REMOVEFILTERS('List Date'))",
    "#,##0");

// Email Details Rate: % of patients with a non-blank email address
add("Email Details Rate",
    @"DIVIDE(
    CALCULATE(
        COUNTROWS('List Patients'),
        NOT ISBLANK('List Patients'[Email Address])),
    COUNTROWS('List Patients'))",
    "#,##0.0%");

// Phone Details Rate: % of patients with at least one phone number (mobile or home)
add("Phone Details Rate",
    @"DIVIDE(
    CALCULATE(
        COUNTROWS('List Patients'),
        NOT ISBLANK('List Patients'[Mobile Phone])
        || NOT ISBLANK('List Patients'[Home Phone])),
    COUNTROWS('List Patients'))",
    "#,##0.0%");

// ── Target measures ───────────────────────────────────────────────────────────

add("Average Plan Value Target",
    @"MAXX(FILTER('_Targets', '_Targets'[Metric] = ""avg_plan_value""),
    '_Targets'[Target Value])",
    "£#,##0");

add("Average Plan Value vs Target",
    @"VAR actual = [Average Plan Value]
VAR target = [Average Plan Value Target]
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Cancellation Frequency Target",
    @"MAXX(FILTER('_Targets', '_Targets'[Metric] = ""cancellation_frequency""),
    '_Targets'[Target Value])",
    "#,##0");

add("Cancellation Frequency vs Target",
    @"VAR actual = [Cancellation Frequency]
VAR target = [Cancellation Frequency Target]
VAR pct    = DIVIDE(target - actual, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Short Notice Cancellation Rate Target",
    @"MAXX(FILTER('_Targets', '_Targets'[Metric] = ""short_notice_cancellation_rate""),
    '_Targets'[Target Value])",
    "#,##0.0%");

add("Short Notice Cancellation Rate vs Target",
    @"VAR actual  = [Short Notice Cancellation Rate]
VAR target  = [Short Notice Cancellation Rate Target]
VAR diff_pp = (target - actual) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("Overdue Recalls Target",
    @"MAXX(FILTER('_Targets', '_Targets'[Metric] = ""overdue_recalls""),
    '_Targets'[Target Value])",
    "#,##0");

add("Overdue Recalls vs Target",
    @"VAR actual = [Overdue Recalls]
VAR target = [Overdue Recalls Target]
VAR pct    = DIVIDE(target - actual, ABS(target)) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(pct >= 0,
        ""▲ "" & FORMAT(pct,      ""0.0"") & ""%"",
        ""▼ "" & FORMAT(ABS(pct), ""0.0"") & ""%""))",
    "");

add("Email Details Rate Target",
    @"MAXX(FILTER('_Targets', '_Targets'[Metric] = ""email_details_rate""),
    '_Targets'[Target Value])",
    "#,##0.0%");

add("Email Details Rate vs Target",
    @"VAR actual  = [Email Details Rate]
VAR target  = [Email Details Rate Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

add("Phone Details Rate Target",
    @"MAXX(FILTER('_Targets', '_Targets'[Metric] = ""phone_details_rate""),
    '_Targets'[Target Value])",
    "#,##0.0%");

add("Phone Details Rate vs Target",
    @"VAR actual  = [Phone Details Rate]
VAR target  = [Phone Details Rate Target]
VAR diff_pp = (actual - target) * 100
RETURN IF(
    ISBLANK(target), BLANK(),
    IF(diff_pp >= 0,
        ""▲ "" & FORMAT(diff_pp,      ""0.0"") & ""pp"",
        ""▼ "" & FORMAT(ABS(diff_pp), ""0.0"") & ""pp""))",
    "");

// ── BG colour measures ────────────────────────────────────────────────────────
// avg_plan_value            → above + currency → relative %
// cancellation_frequency    → below + count   → relative %
// short_notice_cancellation → below + percent → absolute pp
// overdue_recalls           → below + count   → relative %
// email/phone_details_rate  → above + percent → absolute pp

add("Average Plan Value BG",
    @"VAR actual = [Average Plan Value]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""avg_plan_value""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""avg_plan_value""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct >= band,     ""#1a7f3c"",
    pct >= 0,        ""#6abf7b"",
    pct >= -band,    ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Cancellation Frequency BG",
    @"VAR actual = [Cancellation Frequency]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""cancellation_frequency""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""cancellation_frequency""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Short Notice Cancellation Rate BG",
    @"VAR actual  = [Short Notice Cancellation Rate]
VAR target  = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""short_notice_cancellation_rate""), '_Targets'[Target Value])
VAR band    = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""short_notice_cancellation_rate""), '_Targets'[Variance])
VAR diff_pp = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp <= -band, ""#1a7f3c"",
    diff_pp <= 0,     ""#6abf7b"",
    diff_pp <= band,  ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Overdue Recalls BG",
    @"VAR actual = [Overdue Recalls]
VAR target = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""overdue_recalls""), '_Targets'[Target Value])
VAR band   = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""overdue_recalls""), '_Targets'[Variance])
VAR pct    = DIVIDE(actual - target, ABS(target)) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target), ""#FFFFFF"",
    pct <= -band,    ""#1a7f3c"",
    pct <= 0,        ""#6abf7b"",
    pct <= band,     ""#f4a261"",
                     ""#c0392b"")",
    "");

add("Email Details Rate BG",
    @"VAR actual  = [Email Details Rate]
VAR target  = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""email_details_rate""), '_Targets'[Target Value])
VAR band    = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""email_details_rate""), '_Targets'[Variance])
VAR diff_pp = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")",
    "");

add("Phone Details Rate BG",
    @"VAR actual  = [Phone Details Rate]
VAR target  = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""phone_details_rate""), '_Targets'[Target Value])
VAR band    = MAXX(FILTER('_Targets', '_Targets'[Metric] = ""phone_details_rate""), '_Targets'[Variance])
VAR diff_pp = (actual - target) * 100
RETURN SWITCH(TRUE(),
    ISBLANK(target),  ""#FFFFFF"",
    diff_pp >= band,  ""#1a7f3c"",
    diff_pp >= 0,     ""#6abf7b"",
    diff_pp >= -band, ""#f4a261"",
                      ""#c0392b"")",
    "");

Info("Home Detail KPI measures created.");
