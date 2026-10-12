"""Add a Lost Patients bookmark pair to the Patient report.

Two visuals on the existing main page, two new bookmarks, and the four existing bookmarks
updated to hide the newcomers (a bookmark only controls visuals named in its targetVisualNames,
so a visual missing from that list stays visible on every tab).

  Lost Patients       stacked column -- lapsed count by month, split by the two causes
  Lost Patient List   table -- the 24-month non-attenders, with contact details

Both are driven by _Lapsed Patients, which is a FACT related to List Date on the lapsed date,
so the app's period filter scopes them normally. List Patients is deliberately NOT related to
List Date (the owner avoids dim-to-dim joins, which is why lapsed and new patients are facts at
all), so its columns ride along as attributes of the lapsed rows.

Templates are copied from visuals already in this report rather than hand-built, so the envelope
(schema version, objects, theme) matches whatever Desktop last wrote.
"""
import copy
import json
import pathlib

REPORT = pathlib.Path(r"C:\Users\aihig\OneDrive\Dentally\Code\PBI\Patient.Report\definition")
PAGE = "146989b88eb26d71b830"
PAGES = REPORT / "pages" / PAGE / "visuals"
BOOKMARKS = REPORT / "bookmarks"

BAR_TPL = PAGES / "59450b97013af8b3a0a6" / "visual.json"          # columnChart, Category/Series/Y
TBL_TPL = (REPORT / "pages" / "75859622dd416a8d8410" / "visuals"
           / "a69aab84ce30de0c7377" / "visual.json")              # tableEx contact list

BAR = "1a7c4e9b02f5d6380011"
TBL = "1a7c4e9b02f5d6380033"
BM_BAR = "1a7c4e9b02f5d6380044"
BM_TBL = "1a7c4e9b02f5d6380055"

LAPSED = "_Lapsed Patients"
PATIENTS = "List Patients"
CALC = "Calculated as inactive"


def col(entity, prop, native=None):
    return {"field": {"Column": {"Expression": {"SourceRef": {"Entity": entity}},
                                 "Property": prop}},
            "queryRef": "%s.%s" % (entity, prop),
            "nativeQueryRef": native or prop}


def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    # UTF-8 WITHOUT a BOM -- a BOM stops Power BI Desktop opening the report at all.
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


# ── 1. the stacked bar ───────────────────────────────────────────────────────────────────
bar = json.loads(BAR_TPL.read_text(encoding="utf-8"))
bar["name"] = BAR
bar["position"] = {"x": 0, "y": 80, "z": 0, "height": 424, "width": 1280, "tabOrder": 0}
bar["visual"]["query"] = {"queryState": {
    "Category": {"projections": [col("List Date", "Month Commencing Date")]},
    "Series":   {"projections": [col(LAPSED, "Lapsed Type")]},
    "Y":        {"projections": [dict(col(LAPSED, "Lapsed Patient Count"),
                                      **{"queryRef": "Sum(%s.Lapsed Patient Count)" % LAPSED})]},
}}
# Sum the count column explicitly; a bare column projection on Y renders as First() in some builds.
bar["visual"]["query"]["queryState"]["Y"]["projections"][0]["field"] = {
    "Aggregation": {"Expression": {"Column": {
        "Expression": {"SourceRef": {"Entity": LAPSED}}, "Property": "Lapsed Patient Count"}},
        "Function": 0}}
bar["visual"].setdefault("visualContainerObjects", {})["title"] = [
    {"properties": {"text": {"expr": {"Literal": {"Value": "'Lost Patients by Month and Cause'"}}}}}]
bar.pop("filterConfig", None)
bar["isHidden"] = True
write_json(PAGES / BAR / "visual.json", bar)

# ── 2. the detail list ───────────────────────────────────────────────────────────────────
tbl = json.loads(TBL_TPL.read_text(encoding="utf-8"))
tbl["name"] = TBL
tbl["position"] = {"x": 0, "y": 80, "z": 0, "height": 424, "width": 1280, "tabOrder": 0}
# ==> COLUMNS, NOT MEASURES. <== A measure in a tableEx projection kills auto-exist and
# multiplies the rows out; every one of these is a real column on its table.
tbl["visual"]["query"] = {"queryState": {"Values": {"projections": [
    col(PATIENTS, "Full Name"),
    col(PATIENTS, "Last Appointment Date"),
    col(LAPSED,   "Lapsed Date"),
    col(LAPSED,   "Lapsed Reason"),
    col(PATIENTS, "Mobile Phone"),
    col(PATIENTS, "Email Address"),
    col(PATIENTS, "Marketing Consent"),
    col(PATIENTS, "Total Paid"),
]}}}
# Only the 24-month non-attenders: the ones still ACTIVE in Dentally who can still be contacted.
# "Set as inactive" is the other half of the bar and is deliberately NOT in this list.
tbl["filterConfig"] = {"filters": [{
    "name": "1a7c4e9b02f5d63800f1",
    "field": {"Column": {"Expression": {"SourceRef": {"Entity": LAPSED}}, "Property": "Lapsed Type"}},
    "type": "Categorical",
    "filter": {"Version": 2,
               "From": [{"Name": "l", "Entity": LAPSED, "Type": 0}],
               "Where": [{"Condition": {"In": {
                   "Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "l"}},
                                               "Property": "Lapsed Type"}}],
                   "Values": [[{"Literal": {"Value": "'%s'" % CALC}}]]}}}]},
    "howCreated": 1,
}]}
tbl["visual"].setdefault("visualContainerObjects", {})["title"] = [
    {"properties": {"text": {"expr": {"Literal": {"Value":
        "'Lost -- no visit in 24+ months, still active in Dentally'"}}}}}]
tbl["isHidden"] = True
write_json(PAGES / TBL / "visual.json", tbl)

# ── 3. bookmarks ─────────────────────────────────────────────────────────────────────────
existing = sorted(p for p in BOOKMARKS.glob("*.bookmark.json"))
first = json.loads(existing[0].read_text(encoding="utf-8"))
all_targets = list(first["options"]["targetVisualNames"])
for n in (BAR, TBL):
    if n not in all_targets:
        all_targets.append(n)

types = {BAR: "columnChart", TBL: "tableEx"}
for d in PAGES.iterdir():
    f = d / "visual.json"
    if f.exists():
        types.setdefault(d.name, json.loads(f.read_text(encoding="utf-8"))["visual"]["visualType"])


def state(show):
    vcs = {}
    for n in all_targets:
        e = {"visualType": types.get(n, "columnChart"), "objects": {}}
        if n not in show:
            e["display"] = {"mode": "hidden"}
        vcs[n] = {"singleVisual": e}
    return vcs


# the four existing bookmarks: keep their own shown set, add the newcomers as hidden
for f in existing:
    b = json.loads(f.read_text(encoding="utf-8"))
    b["options"]["targetVisualNames"] = all_targets
    vcs = b["explorationState"]["sections"][PAGE]["visualContainers"]
    for n in (BAR, TBL):
        vcs[n] = {"singleVisual": {"visualType": types[n], "objects": {},
                                   "display": {"mode": "hidden"}}}
    write_json(f, b)
    print("   updated bookmark %-20s (%s)" % (b.get("displayName"), f.name))

SCHEMA = first["$schema"]
for name, display, shown in ((BM_BAR, "Lost Patients", {BAR}),
                             (BM_TBL, "Lost Patient List", {TBL})):
    bm = {"$schema": SCHEMA, "displayName": display, "name": name,
          "options": {"applyOnlyToTargetVisuals": True,
                      "targetVisualNames": all_targets, "suppressData": True},
          "explorationState": {"version": "1.0", "activeSection": PAGE,
                               "sections": {PAGE: {"visualContainers": state(shown)}}}}
    write_json(BOOKMARKS / ("%s.bookmark.json" % name), bm)
    print("   created bookmark %s" % display)

meta = json.loads((BOOKMARKS / "bookmarks.json").read_text(encoding="utf-8"))
have = {i["name"] for i in meta["items"]}
for n in (BM_BAR, BM_TBL):
    if n not in have:
        meta["items"].append({"name": n})
write_json(BOOKMARKS / "bookmarks.json", meta)
print("   bookmarks.json now lists %d" % len(meta["items"]))
print("\nvisuals written: %s (bar), %s (list)" % (BAR, TBL))
