// =====================================================================
// Appointment Journey -- model side for the SCALABLE (Gold-view-backed) Alluvial
// =====================================================================
// The journey is now PRECOMPUTED in Gold and exposed as a mode-long view:
//   Gold.Fact_Appointment_Journey      -- appt-grain base, 4 next-pointers, full rebuild
//   Gold.vw_Fact_Appointment_Journey   -- one row per (appt x qualifying mode),
//                                         Delay / Next Appointment / Current State as COLUMNS
//   PBI.[_Appointment Journey]         -- the presentation view (import into the model)
//
// Because the stages are COLUMNS (not dynamic measures) and 'Mode' is a real column,
// Power BI aggregates server-side and Deneb only ever receives the distinct
// stage-combinations -- so the Alluvial scales to any tenant volume (no 30k data cap).
//
// This RETIRES the old dynamic approach: the per-appointment look-ahead measures
// (Delay / Next Appointment / Current State / Next Appt Start / Journey Current
// Matches / Journey Count gate) and the disconnected 'Journey Filter' slicer are
// gone. The only measure left is a plain COUNT weight.
//
// ORDER: import the '_Appointment Journey' table FIRST, then run this, then Save.
// =====================================================================

var jmTable  = Model.Tables["_Measures"];
var jmFolder = "Appointment Journey";

// Retire every old Appointment Journey measure (the dynamic look-ahead set).
foreach (var existing in jmTable.Measures.Where(x => x.DisplayFolder == jmFolder).ToList())
    existing.Delete();

// Single weight: one row per appointment in the (mode-filtered) view. The mode gate
// is baked into the view, so this is an un-gated plain count.
var jc = jmTable.AddMeasure("Journey Count", "COUNTROWS('_Appointment Journey')");
jc.DisplayFolder = jmFolder;
jc.FormatString  = "#,##0";

Info(
    "Appointment Journey: retired the old dynamic measures; added [Journey Count] = " +
    "COUNTROWS('_Appointment Journey').\n" +
    "MANUAL (step 4): (1) import PBI.[_Appointment Journey]; (2) point the Deneb Alluvial " +
    "at its columns Booking / Appointment Reason / Delay / Next Appointment / Current State " +
    "+ the [Journey Count] measure (NO bk Appointment ID); (3) put '_Appointment Journey'[Mode] " +
    "on the slicer and DELETE the old disconnected 'Journey Filter' table; (4) publish."
);
