var t = Model.Tables["_Measures"];
var g = "Patient Cohorts";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

// Distinct patients meeting a condition, counted ONCE. Pattern:
//   CALCULATE(DISTINCTCOUNT(fact[fk Patient]), <pre-computed flag>)
// The flags are BIT columns computed in the Gold load (Is_Discount /
// Is_Invoice_Outstanding on Fact_Invoice_Items, Is_Deposit on Fact_Payments,
// Is_Email_Missing / Is_Phone_Missing on Dim_Patients), so the DAX stays a
// one-line CALCULATE rather than complex logic or wide per-condition FK columns.

// -- Financial cohorts: distinct patients tied to an invoice/payment condition --

add("Patients With Discount",
    @"CALCULATE(DISTINCTCOUNT('_Invoice Items'[fk Patient]), '_Invoice Items'[Is Discount] = TRUE())",
    "#,##0");

add("Patients With Outstanding Invoice",
    @"CALCULATE(DISTINCTCOUNT('_Invoice Items'[fk Patient]), '_Invoice Items'[Is Invoice Outstanding] = TRUE())",
    "#,##0");

add("Patients With Deposit",
    @"CALCULATE(DISTINCTCOUNT('_Payments'[fk Patient]), '_Payments'[Is Deposit] = TRUE())",
    "#,##0");

// -- Reception data-capture gaps --
// Distinct patients who ATTENDED (Is Arrived) but still lack the detail. Counted
// once per patient; period/site/practitioner-aware via the appointment fact;
// excludes never-attended patients (no capture opportunity) and DNAs/cancellations.

add("Patients Email Not Captured",
    @"CALCULATE(
    DISTINCTCOUNT('_Appointments'[fk Patient]),
    'List Patients'[Is Email Missing] = TRUE(),
    '_Appointments'[Is Arrived] = TRUE())",
    "#,##0");

add("Patients Phone Not Captured",
    @"CALCULATE(
    DISTINCTCOUNT('_Appointments'[fk Patient]),
    'List Patients'[Is Phone Missing] = TRUE(),
    '_Appointments'[Is Arrived] = TRUE())",
    "#,##0");

Info("Patient Cohort measures created.");
