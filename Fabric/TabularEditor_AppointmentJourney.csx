// =====================================================================
// Appointment Journey DAX -- feeds the Deneb Alluvial (PBI/Deneb_Alluvial_Spec.json)
// =====================================================================
// Replaces the former materialised journey columns (Delay / Next_Appointment /
// Current_State, dropped from Gold.Fact_Appointments in V008) with DYNAMIC
// measures computed from the appointment self-relationship, so they respond to an
// Include/Exclude HYGIENE slicer. Booking + Appointment_Reason stay as columns on
// '_Appointments'.
//
// Deneb setup (in PBI, not here): put '_Appointments'[bk Appointment ID] (hidden) in
// the visual's Values so the dataset is one row per appointment, then add the columns
// [Booking],[Appointment Reason] and the measures [Delay],[Next Appointment],
// [Current State],[Patient Count]. The Alluvial does its own aggregation.
//
// ASSUMPTIONS (validate in the model): a hygiene appointment is
// '_Appointments'[Appointment Reason] = "Hygiene"; 'List Patients'[Active] exists and
// is boolean (bit). Current_State is the SIMPLIFIED form -- the four recall sub-states
// collapse to "In Recall Process"; recall detail lives in its own report. "Treatment
// BBYL" is inferred from the next active appointment's [Booking] (BBYL/Online = via API),
// since Booked_Via_API is not on the fact.
// Run in Tabular Editor against the 'PBI Dentally' model, then Save to model.
// =====================================================================

// ── Hygiene toggle (disconnected slicer table) ───────────────────────────────
if (Model.Tables.Any(t => t.Name == "Hygiene Toggle"))
    Model.Tables["Hygiene Toggle"].Delete();
var hyg = Model.AddCalculatedTable("Hygiene Toggle",
    "DATATABLE(\"Mode\", STRING, {{\"Include Hygiene\"}, {\"Exclude Hygiene\"}})");
hyg.Description = "Disconnected slicer: include or exclude Hygiene appointments from the journey 'next appointment' calculation.";

var t = Model.Tables["_Measures"];
var g = "Appointment Journey";

foreach (var m in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    m.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// ── Helper: chronologically next non-cancelled/non-DNA appointment start ──────
// (hidden; the other measures build on it). Hygiene-aware.
add("Next Appt Start", @"
VAR cur     = SELECTEDVALUE('_Appointments'[Start Time])
VAR pat     = SELECTEDVALUE('_Appointments'[fk Patient])
VAR tid     = SELECTEDVALUE('_Appointments'[Tenant ID])
VAR exclHyg = SELECTEDVALUE('Hygiene Toggle'[Mode], ""Include Hygiene"") = ""Exclude Hygiene""
RETURN
IF( NOT ISBLANK(cur) && NOT ISBLANK(pat),
    CALCULATE(
        MIN('_Appointments'[Start Time]),
        FILTER( ALL('_Appointments'),
            '_Appointments'[fk Patient]  = pat
            && '_Appointments'[Tenant ID] = tid
            && '_Appointments'[Start Time] > cur
            && '_Appointments'[Is Cancelled] = 0
            && '_Appointments'[Is DNA]       = 0
            && ( NOT exclHyg || '_Appointments'[Appointment Reason] <> ""Hygiene"" )
        )
    )
)", "");
t.Measures["Next Appt Start"].IsHidden = true;

// ── Delay: banded gap to the next appointment ────────────────────────────────
add("Delay", @"
VAR cur = SELECTEDVALUE('_Appointments'[Start Time])
VAR nxt = [Next Appt Start]
VAR d   = DATEDIFF(cur, nxt, DAY)
RETURN
SWITCH( TRUE(),
    ISBLANK(nxt), ""No Future Appointment"",
    d = 0,   ""Same Day"",
    d <= 30, ""Within 1 Month"",
    d <= 182,""Within 6 Months"",
    d <= 365,""Within 12 Months"",
    ""More than 12 Months"" )", "");

// ── Next Appointment: reason of the next appointment (Emergency -> Exam) ──────
add("Next Appointment", @"
VAR pat     = SELECTEDVALUE('_Appointments'[fk Patient])
VAR tid     = SELECTEDVALUE('_Appointments'[Tenant ID])
VAR nxt     = [Next Appt Start]
VAR reason  =
    CALCULATE(
        MIN('_Appointments'[Appointment Reason]),
        FILTER( ALL('_Appointments'),
            '_Appointments'[fk Patient]  = pat
            && '_Appointments'[Tenant ID] = tid
            && '_Appointments'[Start Time] = nxt
            && '_Appointments'[Is Cancelled] = 0
            && '_Appointments'[Is DNA]       = 0 )
    )
RETURN
SWITCH( TRUE(),
    ISBLANK(nxt),        ""No Future Appointment"",
    reason = ""Emergency"", ""Exam"",
    reason )", "");

// ── Current State: post-visit status (simplified; recall detail -> own report) ─
add("Current State", @"
VAR cur     = SELECTEDVALUE('_Appointments'[Start Time])
VAR pat     = SELECTEDVALUE('_Appointments'[fk Patient])
VAR tid     = SELECTEDVALUE('_Appointments'[Tenant ID])
VAR exclHyg = SELECTEDVALUE('Hygiene Toggle'[Mode], ""Include Hygiene"") = ""Exclude Hygiene""
VAR baseFilter =
    FILTER( ALL('_Appointments'),
        '_Appointments'[fk Patient]  = pat
        && '_Appointments'[Tenant ID] = tid
        && '_Appointments'[Start Time] > cur
        && ( NOT exclHyg || '_Appointments'[Appointment Reason] <> ""Hygiene"" ) )
-- a later COMPLETED visit exists
VAR seenAgain =
    CALCULATE( COUNTROWS('_Appointments'),
        baseFilter, '_Appointments'[Is Completed] = 1 ) > 0
-- the chronologically next ACTIVE (uncompleted, non-cancelled, non-DNA) booking
VAR nextActiveStart =
    CALCULATE( MIN('_Appointments'[Start Time]),
        baseFilter, '_Appointments'[Is Completed] = 0,
        '_Appointments'[Is Cancelled] = 0, '_Appointments'[Is DNA] = 0 )
VAR nextActiveBooking =
    CALCULATE( MIN('_Appointments'[Booking]),
        ALL('_Appointments'),
        '_Appointments'[fk Patient]  = pat, '_Appointments'[Tenant ID] = tid,
        '_Appointments'[Start Time] = nextActiveStart,
        '_Appointments'[Is Completed] = 0, '_Appointments'[Is Cancelled] = 0, '_Appointments'[Is DNA] = 0 )
VAR hasActive = NOT ISBLANK(nextActiveStart)
VAR patActive = SELECTEDVALUE('List Patients'[Active])
RETURN
SWITCH( TRUE(),
    seenAgain,                                              ""Seen Again"",
    hasActive && nextActiveBooking IN {""BBYL"", ""Online""}, ""Treatment BBYL"",
    hasActive,                                              ""Treatment Booked"",
    patActive = FALSE(),                                    ""Will Not See Again"",
    ""In Recall Process"" )", "");

// ── Patient Count: the Alluvial weight (one per appointment at appt grain) ────
add("Patient Count", "COUNTROWS('_Appointments')", "#,##0");

Info("Appointment Journey measures + Hygiene Toggle created. Validate in PBI: hygiene = Appointment Reason 'Hygiene'; List Patients[Active] boolean; add bk Appointment ID (hidden) + the 5 fields to the Deneb Alluvial.");
