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

// ── Journey filter table -- CREATE MANUALLY (not here) ───────────────────────
// The 'Journey Filter' disconnected slicer must be made via Home > Enter data:
//   table 'Journey Filter', one column [Mode], four rows:
//     All Appointments | Exclude Hygiene | Exams Only | Hygiene Only
// Leave it unrelated to anything. (Calculated tables added by an external tool
// often won't populate in PBI Desktop -- the slicer shows blank -- so Enter data
// is the reliable route.) The measures below bind to 'Journey Filter'[Mode] by
// name, defaulting to "All Appointments" when nothing is selected.
// Tidy up the obsolete 2-way table if it is still present:
if (Model.Tables.Any(x => x.Name == "Hygiene Toggle"))
    Model.Tables["Hygiene Toggle"].Delete();

var jmTable  = Model.Tables["_Measures"];
var jmFolder = "Appointment Journey";

foreach (var existing in jmTable.Measures.Where(x => x.DisplayFolder == jmFolder).ToList())
    existing.Delete();

Action<string,string,string> addJ = (name, dax, fmt) => {
    var meas = jmTable.AddMeasure(name, dax);
    meas.DisplayFolder = jmFolder;
    if (fmt != "") meas.FormatString = fmt;
};

// ── Helper: chronologically next non-cancelled/non-DNA appointment start ──────
// (hidden; the other measures build on it). Hygiene-aware.
addJ("Next Appt Start", @"
VAR cur     = SELECTEDVALUE('_Appointments'[Start Time])
VAR pat     = SELECTEDVALUE('_Appointments'[fk Patient])
VAR tid     = SELECTEDVALUE('_Appointments'[Tenant ID])
VAR mode = SELECTEDVALUE('Journey Filter'[Mode], ""All Appointments"")
RETURN
IF( NOT ISBLANK(cur) && NOT ISBLANK(pat),
    CALCULATE(
        MIN('_Appointments'[Start Time]),
        FILTER( ALL('_Appointments'),
            '_Appointments'[fk Patient]  = pat
            && '_Appointments'[Tenant ID] = tid
            && '_Appointments'[Start Time] > cur
            && '_Appointments'[Is Cancelled] = FALSE()
            && '_Appointments'[Is DNA]       = FALSE()
            && ( mode = ""All Appointments""
                 || ( mode = ""Exclude Hygiene"" && '_Appointments'[Appointment Reason] <> ""Hygiene"" )
                 || ( mode = ""Exams Only""      && '_Appointments'[Appointment Reason] = ""Exam"" )
                 || ( mode = ""Hygiene Only""    && '_Appointments'[Appointment Reason] = ""Hygiene"" ) )
        )
    )
)", "");
jmTable.Measures["Next Appt Start"].IsHidden = true;

// ── Delay: banded gap to the next appointment ────────────────────────────────
addJ("Delay", @"
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
addJ("Next Appointment", @"
VAR pat     = SELECTEDVALUE('_Appointments'[fk Patient])
VAR tid     = SELECTEDVALUE('_Appointments'[Tenant ID])
VAR mode    = SELECTEDVALUE('Journey Filter'[Mode], ""All Appointments"")
VAR nxt     = [Next Appt Start]
VAR reason  =
    CALCULATE(
        MIN('_Appointments'[Appointment Reason]),
        FILTER( ALL('_Appointments'),
            '_Appointments'[fk Patient]  = pat
            && '_Appointments'[Tenant ID] = tid
            && '_Appointments'[Start Time] = nxt
            && '_Appointments'[Is Cancelled] = FALSE()
            && '_Appointments'[Is DNA]       = FALSE()
            && ( mode = ""All Appointments""
                 || ( mode = ""Exclude Hygiene"" && '_Appointments'[Appointment Reason] <> ""Hygiene"" )
                 || ( mode = ""Exams Only""      && '_Appointments'[Appointment Reason] = ""Exam"" )
                 || ( mode = ""Hygiene Only""    && '_Appointments'[Appointment Reason] = ""Hygiene"" ) ) )
    )
RETURN
SWITCH( TRUE(),
    ISBLANK(nxt),        ""No Future Appointment"",
    reason = ""Emergency"", ""Exam"",
    reason )", "");

// ── Current State: post-visit status (simplified; recall detail -> own report) ─
addJ("Current State", @"
VAR cur     = SELECTEDVALUE('_Appointments'[Start Time])
VAR pat     = SELECTEDVALUE('_Appointments'[fk Patient])
VAR tid     = SELECTEDVALUE('_Appointments'[Tenant ID])
VAR mode = SELECTEDVALUE('Journey Filter'[Mode], ""All Appointments"")
VAR baseFilter =
    FILTER( ALL('_Appointments'),
        '_Appointments'[fk Patient]  = pat
        && '_Appointments'[Tenant ID] = tid
        && '_Appointments'[Start Time] > cur
        && ( mode = ""All Appointments""
             || ( mode = ""Exclude Hygiene"" && '_Appointments'[Appointment Reason] <> ""Hygiene"" )
             || ( mode = ""Exams Only""      && '_Appointments'[Appointment Reason] = ""Exam"" )
             || ( mode = ""Hygiene Only""    && '_Appointments'[Appointment Reason] = ""Hygiene"" ) ) )
-- a later COMPLETED visit exists
-- Filter the baseFilter TABLE explicitly (mixing a table filter with separate
-- column predicates in CALCULATE does not intersect reliably -- it made seenAgain
-- count any later appointment, so Treatment Booked/BBYL collapsed into Seen Again).
VAR seenAgain =
    CALCULATE( COUNTROWS('_Appointments'),
        FILTER( baseFilter, '_Appointments'[Is Completed] = TRUE() ) ) > 0
-- the chronologically next ACTIVE (uncompleted, non-cancelled, non-DNA) booking
VAR nextActiveStart =
    CALCULATE( MIN('_Appointments'[Start Time]),
        FILTER( baseFilter,
            '_Appointments'[Is Completed] = FALSE()
            && '_Appointments'[Is Cancelled] = FALSE()
            && '_Appointments'[Is DNA] = FALSE() ) )
VAR nextActiveBooking =
    CALCULATE( MIN('_Appointments'[Booking]),
        FILTER( baseFilter,
            '_Appointments'[Start Time] = nextActiveStart
            && '_Appointments'[Is Completed] = FALSE()
            && '_Appointments'[Is Cancelled] = FALSE()
            && '_Appointments'[Is DNA] = FALSE() ) )
VAR hasActive = NOT ISBLANK(nextActiveStart)
-- Look the patient up directly (the fact can't filter the patient dim through the
-- single-direction relationship, so SELECTEDVALUE would be BLANK -> mislabels).
VAR patActive = LOOKUPVALUE('List Patients'[Active], 'List Patients'[pk Patient], pat)
RETURN
SWITCH( TRUE(),
    seenAgain,                                              ""Seen Again"",
    hasActive && nextActiveBooking IN {""BBYL"", ""Online""}, ""Treatment BBYL"",
    hasActive,                                              ""Treatment Booked"",
    NOT ISBLANK(patActive) && NOT patActive,               ""Will Not See Again"",
    ""In Recall Process"" )", "");

// ── Patient Count: the Alluvial weight (one per appointment at appt grain) ────
// Mode also applies to the CURRENT appointment: a current that doesn't match the
// mode returns BLANK so it drops out of the Alluvial (node + flows go to zero).
// So the filter affects BOTH ends -- e.g. Exams Only shows exam -> next-exam.
addJ("Patient Count", @"
VAR mode   = SELECTEDVALUE('Journey Filter'[Mode], ""All Appointments"")
VAR reason = SELECTEDVALUE('_Appointments'[Appointment Reason])
RETURN
IF(
    mode = ""All Appointments""
    || ( mode = ""Exclude Hygiene"" && reason <> ""Hygiene"" )
    || ( mode = ""Exams Only""      && reason = ""Exam"" )
    || ( mode = ""Hygiene Only""    && reason = ""Hygiene"" ),
    COUNTROWS('_Appointments'),
    BLANK() )", "#,##0");

Info("Appointment Journey measures created. NEXT: create the 'Journey Filter' table via Home > Enter data (column 'Mode', rows: All Appointments / Exclude Hygiene / Exams Only / Hygiene Only), leave it disconnected, put Mode on a slicer. Then add bk Appointment ID (hidden) + the 5 fields to the Deneb Alluvial.");
