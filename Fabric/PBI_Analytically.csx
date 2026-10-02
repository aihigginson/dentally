// PBI_Analytically.csx -- measures for PBI Analytically.pbix, one atomic apply.
//
// Run in Tabular Editor against the model, same as Fabric/PBI_Dentally.csx: one paste, one Run.
// Every section is wrapped in its own scope block { } so local helpers cannot collide, and each
// DisplayFolder is CLEARED before it is rebuilt -- so re-running is idempotent and measures keep
// their exact names, which is what lets report cards re-bind without being re-pointed.
//
// ==> THIS IS THE VENDOR MODEL. IT MUST NEVER BECOME PBI Dentally. <== It carries prospect email
// domains, which practice has gone quiet, and (once added) affiliate commission. No RLS protects
// any of it; the control is that no practice login can open this model at all. A tenant-bearing
// table added to PBI Dentally inherits NO RLS rule, so the separation is the whole safeguard.
//
// ==> AFFILIATE MEASURES ARE NOT IN HERE, AND THAT IS DELIBERATE. <== They were built by hand in
// Desktop and exist only in the old PBI Affiliates dataset; nothing in this repository defines
// them. They could not be read out from here (executeQueries blocks INFO.MEASURES and ADOMD.NET
// is not installed on this machine), and commission is vendor money -- the last thing to
// reconstruct from guesswork. Copy them across from the old model, or paste them in and they can
// be folded into this script so the model is reproducible from source like PBI Dentally is.
//
// WHAT THE TABLES MEAN, because two of them are the same dimension twice:
//   '_Client Status'              ONE ROW PER CLIENT. A summary fact, not an event fact.
//   'List Client'                 the commercial company: customer, prospect, demo or us.
//   'List Sales Status Funnel'    role-playing copy 1 -- how far they got.
//   'List Sales Status Access'    role-playing copy 2 -- whether they actually use it.
// The fact holds two foreign keys to the same status dimension and only one relationship can be
// active, which is why there are two copies rather than USERELATIONSHIP in every measure.

// ===================== Measures table =====================
{
// PBI Analytically has no _Measures table of its own, and measures parked on a data table make
// the field list confusing once there are twenty of them. A one-row disconnected calculated table
// is the same shape PBI Dentally uses.
var mt = Model.Tables.FirstOrDefault(x => x.Name == "_Measures");
if (mt == null)
{
    mt = Model.AddCalculatedTable("_Measures", "ROW(\"_\", 1)");
    Info("_Measures created (one-row disconnected table to hold measures).");
}
mt.IsHidden = false;                 // the folder tree is the navigation; hiding it hides them all
foreach (var c in mt.Columns) c.IsHidden = true;   // the placeholder column is noise
}

// ===================== Client Health =====================
{
var t = Model.Tables["_Measures"];
var g = "Client Health";

foreach (var m in t.Measures.Where(m => m.DisplayFolder == g).ToList()) m.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ==> THE BASE COUNT IS NOT FILTERED, ON PURPOSE. <== Baking Is Vendor = FALSE into it would make
// a page sliced to Analytically show zero, which reads as a bug. Put Is Vendor = False on the page
// filter for a customer view, and use the named measures below when the intent is specific.
add("Clients",
    @"COUNTROWS('_Client Status')",
    "#,##0");

// ==> 91% OF ALL LOGGED USAGE IS OURS. <== Our support accounts are provisioned as customer users
// so we can see what a practice sees, so anything that looks like engagement must exclude the
// vendor explicitly or it flatters every customer.
add("Customers",
    @"CALCULATE(
    [Clients],
    'List Client'[Is Vendor] = FALSE(),
    'List Client'[Is Prospect] = FALSE(),
    'List Client'[Is Demo] = FALSE())",
    "#,##0");

add("Prospects",
    @"CALCULATE([Clients], 'List Client'[Is Prospect] = TRUE())",
    "#,##0");

// The monitoring requirement, as a number. Has Access Gap is computed in
// Gold.usp_Load_Fact_Client_Status -- an ACTIVE client that nobody is using -- so the definition
// lives in one place rather than being restated in DAX where it could drift.
add("Clients at Risk",
    @"CALCULATE([Clients], '_Client Status'[Has Access Gap] = TRUE())",
    "#,##0");

// Worth separating from "at risk": a client nobody has EVER signed into needs a different
// conversation from one that used it and stopped.
add("Clients Never Accessed",
    @"CALCULATE(
    [Clients],
    'List Client'[Is Vendor] = FALSE(),
    '_Client Status'[fk Date Last Access] = -1)",
    "#,##0");

add("Clients Dormant 30d+",
    @"CALCULATE(
    [Clients],
    'List Client'[Is Vendor] = FALSE(),
    '_Client Status'[Days Since Last Access] >= 30)",
    "#,##0");

// Slipping is the window where something can still be done about it.
add("Clients Slipping 8-29d",
    @"CALCULATE(
    [Clients],
    'List Client'[Is Vendor] = FALSE(),
    '_Client Status'[Days Since Last Access] >= 8,
    '_Client Status'[Days Since Last Access] <= 29)",
    "#,##0");

add("At Risk %",
    @"DIVIDE([Clients at Risk], [Customers])",
    "0.0%");
}

// ===================== Client Usage =====================
{
var t = Model.Tables["_Measures"];
var g = "Client Usage";

foreach (var m in t.Measures.Where(m => m.DisplayFolder == g).ToList()) m.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// The three figures the monitor was asked for. The fact is already one row per client, so these
// are plain aggregations -- no iterator needed, and none wanted.
add("Days Accessed",
    @"SUM('_Client Status'[Days Accessed])",
    "#,##0");

// ==> NEVER SUM THIS. <== '_Client Status' is PRE-AGGREGATED to one row per client, so adding
// "days since last access" across clients produces a number with no meaning (22 + 0 = "22 days"?).
// MAX over a single client is that client's figure; over several it is the worst of them, which is
// the one worth looking at. There is no correct SUM, which is why no SUM version exists.
add("Days Since Last Access",
    @"MAX('_Client Status'[Days Since Last Access])",
    "#,##0");

add("Longest Silence (days)",
    @"CALCULATE(
    MAX('_Client Status'[Days Since Last Access]),
    'List Client'[Is Vendor] = FALSE())",
    "#,##0");

// ==> REPORT OPENS BEFORE 2026-10-02 ARE INFLATED UP TO 10x. <== Until the preload was disabled
// that morning, every page load embedded the first section AND nine more whether anyone looked at
// them or not, so one login logged ten opens. Days Accessed is unaffected -- a day is a day --
// which is why it is the figure to trend across that cutover.
add("Reports Accessed",
    @"SUM('_Client Status'[Reports Accessed])",
    "#,##0");

add("Reports Breadth",
    @"MAX('_Client Status'[Reports Breadth])",
    "#,##0");

add("Avg Days Accessed per Customer",
    @"DIVIDE(
    CALCULATE(SUM('_Client Status'[Days Accessed]),
              'List Client'[Is Vendor] = FALSE(), 'List Client'[Is Prospect] = FALSE()),
    [Customers])",
    "#,##0.0");

// Reads as a sentence on a card, and avoids a blank tile for a client that has never signed in --
// blank there looks like a broken measure rather than the fact it is reporting.
add("Last Access Label",
    @"VAR d = MAX('_Client Status'[Days Since Last Access])
VAR ever = MAX('_Client Status'[fk Date Last Access])
RETURN SWITCH(TRUE(),
    ISBLANK(ever) || ever = -1, ""never accessed"",
    d = 0,  ""today"",
    d = 1,  ""yesterday"",
    FORMAT(d, ""#,##0"") & "" days ago"")",
    "");
}

// ===================== Client Users =====================
{
var t = Model.Tables["_Measures"];
var g = "Client Users";

foreach (var m in t.Measures.Where(m => m.DisplayFolder == g).ToList()) m.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// Users Provisioned already EXCLUDES our support accounts -- done in Gold.usp_Load_Dim_Client by
// mailbox domain, because admin@ and grace@ are provisioned into the customer's client so we can
// see what they see, and counting them inflated the practice's own headcount.
add("Users Provisioned",
    @"SUM('_Client Status'[Users Provisioned])",
    "#,##0");

add("Users Ever Accessed",
    @"SUM('_Client Status'[Users Ever Accessed])",
    "#,##0");

// The most actionable number on the board: people who have a licence and have never signed in.
// Maple at the time of writing: 4 provisioned, 1 ever, 3 never.
add("Users Never Accessed",
    @"SUM('_Client Status'[Users Never Accessed])",
    "#,##0");

add("User Activation Rate",
    @"DIVIDE([Users Ever Accessed], [Users Provisioned])",
    "0.0%");
}

// ===================== Client Funnel =====================
{
var t = Model.Tables["_Measures"];
var g = "Client Funnel";

foreach (var m in t.Measures.Where(m => m.DisplayFolder == g).ToList()) m.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// Status Order is the sort within a group, so the furthest stage is simply the highest order
// reached. Reading the NAME through the role-playing dimension keeps the vocabulary in one place.
// ==> RESOLVE THROUGH THE FACT'S KEY, NOT BY MAX OVER THE DIMENSION. <== Two things defeat the
// obvious version, and testing the DAX before shipping it is what surfaced both:
//   1. Relationships propagate dimension -> fact, NOT fact -> dimension. Filtering to one client
//      filters the fact; it does NOT narrow the status dimension, so reading the dimension
//      directly sees every row.
//   2. The role-playing copies hold BOTH status groups, and Status Order restarts per group --
//      Access runs 1..9, Funnel 1..8 -- so MAX(Status Order) returned 9 and resolved to
//      "Vendor (us)", an ACCESS state, as this measure's answer for every single client.
// LOOKUPVALUE on the fact's own foreign key is direction-independent and cannot pick up the wrong
// group, because the key identifies exactly one row.
add("Furthest Funnel Stage",
    @"VAR k = SELECTEDVALUE('_Client Status'[fk Sales Status Funnel])
RETURN LOOKUPVALUE(
    'List Sales Status Funnel'[Status Name],
    'List Sales Status Funnel'[pk Sales Status], k)",
    "");

// The access state resolved the same way, so a table visual can show both without relying on the
// dimension being sliced.
add("Access State",
    @"VAR k = SELECTEDVALUE('_Client Status'[fk Sales Status Access])
RETURN LOOKUPVALUE(
    'List Sales Status Access'[Status Name],
    'List Sales Status Access'[pk Sales Status], k)",
    "");

add("Funnel Stages Reached",
    @"SUM('_Client Status'[Funnel Stages Reached])",
    "#,##0");

// invoice_paid is Status Order 7 and the only stage that is revenue.
add("Clients Converted",
    @"CALCULATE([Clients], 'List Sales Status Funnel'[bk Status Code] = ""invoice_paid"")",
    "#,##0");

add("Conversion Rate",
    @"DIVIDE([Clients Converted], CALCULATE([Clients], 'List Client'[Is Vendor] = FALSE()))",
    "0.0%");

// ==> card_attached AND card_chargeable ARE SEPARATE STAGES FOR A REASON. <== Setup-mode Checkout
// only ATTACHES a card; a customer can hold a perfectly good one with no
// invoice_settings.default_payment_method and still fail to bill. Neither stage is POPULATED yet:
// no Stripe customer exists, so the loader deliberately leaves them empty rather than shipping
// code written against zero rows. These two will read 0 until a real card exists -- that is
// correct, not broken.
add("Cards Supplied",
    @"CALCULATE([Clients], 'List Sales Status Funnel'[bk Status Code] = ""card_attached"")",
    "#,##0");

add("Cards Chargeable",
    @"CALCULATE([Clients], 'List Sales Status Funnel'[bk Status Code] = ""card_chargeable"")",
    "#,##0");
}

// ===================== Traffic lights =====================
{
var t = Model.Tables["_Measures"];
var g = "Client BG";

foreach (var m in t.Measures.Where(m => m.DisplayFolder == g).ToList()) m.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// Colour from the DIMENSION's own Is Gap flag plus the day count, not from a threshold retyped
// here. The thresholds that define the states live in Gold.Dim_Sales_Status; this only renders
// them, so changing "dormant" in one place changes it everywhere.
add("Access State BG",
    @"VAR d    = MAX('_Client Status'[Days Since Last Access])
VAR ever = MAX('_Client Status'[fk Date Last Access])
VAR vend = SELECTEDVALUE('List Client'[Is Vendor])
RETURN SWITCH(TRUE(),
    vend = TRUE(),               ""#FFFFFF"",
    ISBLANK(ever) || ever = -1,  ""#c0392b"",
    d >= 30,                     ""#c0392b"",
    d >= 8,                      ""#f4a261"",
                                 ""#1a7f3c"")",
    "");

// Nobody signed in at all is worse than a low rate, so it is red rather than a pale shade of it.
add("User Activation BG",
    @"VAR r = [User Activation Rate]
RETURN SWITCH(TRUE(),
    ISBLANK(r),   ""#FFFFFF"",
    r = 0,        ""#c0392b"",
    r < 0.5,      ""#f4a261"",
    r < 1,        ""#6abf7b"",
                  ""#1a7f3c"")",
    "");
}

Info("PBI_Analytically.csx applied. Affiliate measures are NOT included -- see the header.");
