// TabularEditor_KillJourney.csx -- run ONCE, then delete this file.
//
// Retiring the Appointment Journey (V241) removes '_Appointment Journey' from the model, but
// the measure that counted it lives on '_Measures', not on that table -- so it survives the
// deletion and sits there reading
//
//     Journey Count = COUNTROWS('_Appointment Journey')
//
// against a table that no longer exists. Tabular Editor reports it as "Objects with errors:
// [Journey Count] -- Expression: Cannot find table '_Appointment Journey'", AFTER the main
// script has run successfully, because it is a MODEL error and not a compile one.
//
// PBI_Dentally.csx used to clean this folder on every run (it deleted before it added).
// That block is gone with the feature, so this does the deletion once instead.
//
// Same one-off purge pattern as TabularEditor_KillDeadSpiders.csx.
//
// RUN: paste into Tabular Editor's Advanced Scripting tab, Run, then SAVE the model.

var killFolder = "Appointment Journey";
var killNames  = new[] { "Journey Count" };

var doomed = Model.Tables.SelectMany(t => t.Measures)
                  .Where(m => m.DisplayFolder == killFolder || killNames.Contains(m.Name))
                  .ToList();

foreach (var m in doomed)
    Info("deleting [" + m.Name + "] from " + m.Table.Name + " (folder: " + m.DisplayFolder + ")");

// ==> DELETE AFTER ENUMERATING, NOT DURING. <== Removing from a collection while iterating it
// is how half a folder survives and the error comes back on the next open.
foreach (var m in doomed)
    m.Delete();

Info(doomed.Count == 0
     ? "Nothing to delete -- the journey measures are already gone."
     : "Deleted " + doomed.Count + " journey measure(s). Save the model now.");
