"""Write the Home-page area weights into PBI_Dentally.csx from Config.Metric_Definitions.

    python Scripts/Generate_Area_Weights.py [--server <fabric endpoint>] [--check]

==> THE WAREHOUSE IS DEFINITIVE; THE csx COPY IS DERIVED. <== The owner's instruction was that the
weights live on the metric register "because they are visible there and if we want to do something
else like alerting, we can access them". The model cannot read the warehouse at build time --
PBI_Dentally.csx is a Tabular Editor script with no SQL connection -- so this generator carries
them across and the result is committed. Run it whenever a weight or an area changes, then re-run
the csx and republish.

It also generates the area MEMBERSHIP, which matters more than it looks. Those five lists used to
be maintained by hand inside the csx, and they had drifted: Patients scored New Patients and Lapsed
Patients while the page DISPLAYED Patient Growth, and Scheduling scored Chair Utilisation while
displaying Diary Fill. So the Patients header read green with growth at -22 -- the number on the
screen was never in the calculation. Generating both from one source is what stops that recurring.

--check exits non-zero if the file is out of date, for CI.
"""
import argparse
import os
import pathlib
import re
import struct
import sys
import subprocess

CSX = pathlib.Path(__file__).resolve().parent.parent / "Fabric" / "PBI_Dentally.csx"
BEGIN, END = "// BEGIN AREA WEIGHTS", "// END AREA WEIGHTS"
NL = "\r\r\n"          # the csx uses double-CR line endings throughout; preserve them
DEV = ("emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem"
       ".datawarehouse.fabric.microsoft.com")

# Section -> the measure name the Home header uses. The register's section is lower case; the
# measure is '<Area> Area RAG'.
AREA_MEASURE = {"revenue": "Revenue Area RAG", "patients": "Patients Area RAG",
                "scheduling": "Scheduling Area RAG", "clinical": "Clinical Area RAG",
                "nhs": "NHS Area RAG"}

# ==> WHERE THE REGISTER AND THE MODEL DISAGREE ON A NAME. <== A BG measure is '<kpi baseName> BG',
# and baseName is normally the register's Display_Name. Three do not match, and silently guessing
# would be worse than failing, so they are declared:
#   deposit_ratio -- the register calls it Deposit Ratio, the tile is labelled Deposit Value. The
#                    tile shows a percentage, so the REGISTER is the accurate one and the label is
#                    the odd one out; renaming the measure is a model change for another day.
# Case-only differences (Revenue per/Per Dentist Hour) are handled by matching case-insensitively.
ALIAS = {"deposit_ratio": "Deposit Value"}


def rows(server):
    """(section, metric_key, display_name, weight) for every weighted metric, in display order."""
    import pyodbc
    tok = subprocess.run(
        ["az", "account", "get-access-token", "--resource", "https://database.windows.net/",
         "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True, shell=True, check=True).stdout.strip()
    packed = tok.encode("utf-16-le")
    cn = pyodbc.connect(
        "Driver={ODBC Driver 18 for SQL Server};Server=tcp:%s,1433;Database=WH_Dentally;"
        "Encrypt=yes;TrustServerCertificate=no;" % server,
        attrs_before={1256: struct.pack("=i", len(packed)) + packed})
    cur = cn.cursor()
    cur.execute("SELECT Section, Metric_Key, Display_Name, CAST(Area_Weight AS INT) "
                "FROM Config.Metric_Definitions "
                "WHERE Area_Weight IS NOT NULL AND Is_Active = 1 "
                "ORDER BY Section, Display_Order")
    out = [tuple(r) for r in cur.fetchall()]
    cn.close()
    return out


def bg_names(text):
    """Every BG measure the csx defines: kpi(baseName, ...) plus the few added directly."""
    names = set(re.findall(r'^\s*kpi\(\s*"([^"]+)"', text, re.M))
    names |= {m[:-3] for m in re.findall(r'add\("([^"]+ BG)"', text)}
    return names


def build(data, available):
    by_area, missing, bad = {}, [], []
    lower = {n.lower(): n for n in available}
    for section, key, display, weight in data:
        if section not in AREA_MEASURE:
            bad.append("%s: section '%s' has no Home area" % (key, section))
            continue
        want = ALIAS.get(key, display)
        hit = lower.get(want.lower())
        if hit is None:
            missing.append("%s (%s)" % (key, want))
            continue
        by_area.setdefault(section, []).append((hit, weight))
    if bad:
        raise SystemExit("area weights: " + "; ".join(bad))
    if missing:
        raise SystemExit(
            "area weights: no BG measure for " + ", ".join(missing) +
            "\n  Either the metric is not on the Home page (clear its Area_Weight), or the model "
            "names it differently (add it to ALIAS in this script).")
    for section, items in by_area.items():
        total = sum(w for _, w in items)
        if total != 100:
            raise SystemExit("area weights: %s sums to %d, not 100" % (section, total))

    lines = [BEGIN]
    for section in ("revenue", "patients", "scheduling", "clinical", "nhs"):
        items = by_area.get(section)
        if not items:
            continue
        bgs = ", ".join('"[%s BG]"' % n for n, _ in items)
        wts = ", ".join(str(w) for _, w in items)
        lines.append('areaRag("%s",' % AREA_MEASURE[section])
        lines.append('    new string[]{ %s },' % bgs)
        lines.append('    new int[]{ %s });' % wts)
    lines.append(END)
    return NL.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default=os.environ.get("FABRIC_SERVER", DEV))
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    raw = CSX.read_bytes().decode("utf-8")
    if BEGIN not in raw or END not in raw:
        raise SystemExit("area weights: the markers are not in %s" % CSX.name)

    generated = build(rows(a.server), bg_names(raw))
    head, rest = raw.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    out = head + generated + tail

    if a.check:
        if out != raw:
            print("OUT OF DATE -- run Scripts/Generate_Area_Weights.py")
            return 1
        print("up to date")
        return 0

    CSX.write_bytes(out.encode("utf-8"))
    n = len([l for l in generated.split(NL) if l.startswith("areaRag(")])
    print("wrote %d area%s into %s from %s"
          % (n, "" if n == 1 else "s", CSX.name, a.server.split(".")[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
