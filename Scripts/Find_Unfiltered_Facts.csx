// ---------------------------------------------------------------------------
// Find_Unfiltered_Facts.csx  --  which tables CAN carry a site filter, and which actually do?
// ---------------------------------------------------------------------------
// Run in Tabular Editor (Advanced Scripting, C# tab). Reports only; changes nothing.
//
// ==> A MEASURE THAT IGNORES THE SITE SELECTOR IS NOT A DAX BUG. <== It is a table with no path
// to 'List Practice Sites'. Open Courses Value, Open Courses and Open (No Appt) read
// '_Treatment Plans', which DOES expose [fk Practice Site] -- so the warehouse is not the
// problem; the relationship is. They read identically on Maple, Demonstration Practice and
// Skeleton Group, which is what "no path" looks like from the outside: not wrong, just global.
//
// Three verdicts per table, and they need different fixes:
//
//   LINKED      a relationship to the site dimension exists. Nothing to do.
//   NEEDS LINK  the table exposes a site key and has NO relationship. MODEL fix, one relationship.
//   NO KEY      the table has no site column at all. WAREHOUSE fix -- the loader must resolve one
//               before any relationship is possible.
//
// Watch for two traps the warehouse audit turned up:
//   * [fk Site] is the LEGACY spelling, renamed to [fk Practice Site] on 2026-10-30. It is
//     still in the list below so a model that has not been re-read yet still reports honestly;
//   * Dim_Patients carries [Site ID] -- the DENTALLY BUSINESS KEY, a varchar -- which cannot
//     relate to [pk Practice Site], an integer surrogate. It LOOKS like a site key and is not one.
// ---------------------------------------------------------------------------

var SITE_DIM = "List Practice Sites";
var siteDim = Model.Tables.FirstOrDefault(x => x.Name == SITE_DIM);
if (siteDim == null) { Info("'" + SITE_DIM + "' is not in the model -- nothing to check against."); return; }

// Anything that could serve as the foreign end of a site relationship.
var SITE_KEYS = new[] { "fk Practice Site", "fk Site", "pk Practice Site" };

var linked = new System.Collections.Generic.List<string>();
var needs  = new System.Collections.Generic.List<string>();
var noKey  = new System.Collections.Generic.List<string>();
var fake   = new System.Collections.Generic.List<string>();

foreach (var t in Model.Tables)
{
    if (t.Name == SITE_DIM) continue;
    // only the things a measure actually aggregates: facts, aggregates and the big dimensions
    var isFactish = t.Name.StartsWith("_") || t.Name.StartsWith("Aggregate ")
                    || t.Name == "List Patients" || t.Name == "List Treatment Plans";
    if (!isFactish) continue;
    if (t.Name == "_Measures") continue;

    var key = t.Columns.FirstOrDefault(c => SITE_KEYS.Contains(c.Name));

    // a relationship to the site dimension, in either direction, active or not
    var rel = Model.Relationships.FirstOrDefault(r =>
        (r.FromTable == t && r.ToTable == siteDim) || (r.ToTable == t && r.FromTable == siteDim));

    if (rel != null)
    {
        linked.Add(t.Name + "  via [" + (rel.FromTable == t ? rel.FromColumn.Name : rel.ToColumn.Name) + "]"
                   + (rel.IsActive ? "" : "   *** INACTIVE -- it will not filter unless USERELATIONSHIP names it ***"));
        continue;
    }

    if (key != null) { needs.Add(t.Name + "  has [" + key.Name + "], no relationship"); continue; }

    // a varchar 'Site ID' is the Dentally business key and cannot be the foreign end
    var looksLike = t.Columns.FirstOrDefault(c => c.Name.Contains("Site"));
    if (looksLike != null)
        fake.Add(t.Name + "  has only [" + looksLike.Name + "] (" + looksLike.DataType
                 + ") -- a business key, not the surrogate");
    else
        noKey.Add(t.Name);
}

var r = new System.Text.StringBuilder();
r.AppendLine("SITE FILTERING, table by table");
r.AppendLine(new string('-', 70));
r.AppendLine();
r.AppendLine("NEEDS LINK -- exposes a site key, no relationship. One relationship each, and the");
r.AppendLine("             measures reading them start responding to the selector:");
r.AppendLine(needs.Count == 0 ? "  (none)" : "  " + string.Join("\n  ", needs));
r.AppendLine();
r.AppendLine("NO SURROGATE -- carries something site-shaped that CANNOT be the foreign end.");
r.AppendLine("             Warehouse fix first: resolve the surrogate in the loader.");
r.AppendLine(fake.Count == 0 ? "  (none)" : "  " + string.Join("\n  ", fake));
r.AppendLine();
r.AppendLine("NO KEY AT ALL -- warehouse fix: the loader must carry a site before anything else:");
r.AppendLine(noKey.Count == 0 ? "  (none)" : "  " + string.Join("\n  ", noKey));
r.AppendLine();
r.AppendLine("LINKED -- already filterable (check for INACTIVE, which looks linked and is not):");
r.AppendLine(linked.Count == 0 ? "  (none)" : "  " + string.Join("\n  ", linked));

Info(r.ToString());
