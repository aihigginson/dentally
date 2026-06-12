// Creates the Sankey Journey calculated table for the Microsoft Sankey visual.
// Each row = one Source→Destination link with a patient count Weight.
// Stage prefixes (Booking:/Reason:/Delay:/Next:/State:) prevent nodes with the
// same label (e.g. "Exam" in both Appointment Reason and Next Appointment) from
// merging into a single node.
// Tenant ID is included so RLS can be applied via relationship in PBI Desktop.

if (Model.Tables.Any(t => t.Name == "Sankey Journey"))
    Model.Tables["Sankey Journey"].Delete();

var dax = @"UNION(

    /* Stage 1 — Booking → Appointment Reason */
    SELECTCOLUMNS(
        FILTER(
            ADDCOLUMNS(
                SUMMARIZE(
                    '_Appointments',
                    '_Appointments'[Tenant ID],
                    '_Appointments'[Booking],
                    '_Appointments'[Appointment Reason]
                ),
                ""Weight_"", CALCULATE(COUNTROWS('_Appointments'))
            ),
            NOT ISBLANK('_Appointments'[Booking])
                && NOT ISBLANK('_Appointments'[Appointment Reason])
        ),
        ""Tenant ID"",   '_Appointments'[Tenant ID],
        ""Source"",      ""Booking: ""  & '_Appointments'[Booking],
        ""Destination"", ""Reason: ""   & '_Appointments'[Appointment Reason],
        ""Weight"",      [Weight_]
    ),

    /* Stage 2 — Appointment Reason → Delay */
    SELECTCOLUMNS(
        FILTER(
            ADDCOLUMNS(
                SUMMARIZE(
                    '_Appointments',
                    '_Appointments'[Tenant ID],
                    '_Appointments'[Appointment Reason],
                    '_Appointments'[Delay]
                ),
                ""Weight_"", CALCULATE(COUNTROWS('_Appointments'))
            ),
            NOT ISBLANK('_Appointments'[Appointment Reason])
                && NOT ISBLANK('_Appointments'[Delay])
        ),
        ""Tenant ID"",   '_Appointments'[Tenant ID],
        ""Source"",      ""Reason: ""   & '_Appointments'[Appointment Reason],
        ""Destination"", ""Delay: ""    & '_Appointments'[Delay],
        ""Weight"",      [Weight_]
    ),

    /* Stage 3 — Delay → Next Appointment */
    SELECTCOLUMNS(
        FILTER(
            ADDCOLUMNS(
                SUMMARIZE(
                    '_Appointments',
                    '_Appointments'[Tenant ID],
                    '_Appointments'[Delay],
                    '_Appointments'[Next Appointment]
                ),
                ""Weight_"", CALCULATE(COUNTROWS('_Appointments'))
            ),
            NOT ISBLANK('_Appointments'[Delay])
                && NOT ISBLANK('_Appointments'[Next Appointment])
        ),
        ""Tenant ID"",   '_Appointments'[Tenant ID],
        ""Source"",      ""Delay: ""    & '_Appointments'[Delay],
        ""Destination"", ""Next: ""     & '_Appointments'[Next Appointment],
        ""Weight"",      [Weight_]
    ),

    /* Stage 4 — Next Appointment → Current State */
    SELECTCOLUMNS(
        FILTER(
            ADDCOLUMNS(
                SUMMARIZE(
                    '_Appointments',
                    '_Appointments'[Tenant ID],
                    '_Appointments'[Next Appointment],
                    '_Appointments'[Current State]
                ),
                ""Weight_"", CALCULATE(COUNTROWS('_Appointments'))
            ),
            NOT ISBLANK('_Appointments'[Next Appointment])
                && NOT ISBLANK('_Appointments'[Current State])
        ),
        ""Tenant ID"",   '_Appointments'[Tenant ID],
        ""Source"",      ""Next: ""     & '_Appointments'[Next Appointment],
        ""Destination"", ""State: ""    & '_Appointments'[Current State],
        ""Weight"",      [Weight_]
    )
)";

var ct = Model.AddCalculatedTable("Sankey Journey", dax);
ct.Description = "Source-Destination-Weight rows for the Microsoft Sankey visual. One row per adjacent stage pair, aggregated by Tenant ID. Stage prefixes prevent cross-stage node merging.";

foreach (var col in ct.Columns)
{
    col.IsHidden = col.Name == "Tenant ID";  // hide Tenant ID from report canvas; used for RLS only
}
