"""Add a 'Revenue Mix' bookmark to the Revenue report: three indexed lines on one axis.

Replaces the three absolute rolling lines, which were unreadable for reasons no reseed could fix
-- a rolling-12M series is a smoother, and three series at wildly different heights on one axis
all read as horizontal. Indexed to 100 at the first visible point they start together and diverge
by relative movement, which is the entire argument: plan climbing, private easing, total flat.

Monthly rather than weekly on the axis: an index line is about shape, and weekly points add
noise without adding information.
"""
import copy
import json
import pathlib

REPORT = pathlib.Path(r"C:\Users\aihig\OneDrive\Dentally\Code\PBI\Revenue.Report\definition")
PAGE = "1731a006301e70a5cd87"
VIS = REPORT / "pages" / PAGE / "visuals"
BM = REPORT / "bookmarks"
TPL = pathlib.Path(r"C:\Users\aihig\OneDrive\Dentally\Code\PBI\Clinical.Report\definition"
                   r"\pages\146989b88eb26d71b830\visuals\6abb0b843af7003c3ff9\visual.json")

MIX = "2c9f1d7a44b8e0350021"
BM_MIX = "2c9f1d7a44b8e0350042"


def write(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def meas(name):
    return {"field": {"Measure": {"Expression": {"SourceRef": {"Entity": "_Measures"}},
                                  "Property": name}},
            "queryRef": "_Measures.%s" % name, "nativeQueryRef": name}


# ── the visual ───────────────────────────────────────────────────────────────────────────
v = json.loads(TPL.read_text(encoding="utf-8"))
v["name"] = MIX
v["position"] = {"x": 0, "y": 80, "z": 0, "height": 424, "width": 1280, "tabOrder": 0}
v["visual"]["query"] = {"queryState": {
    "Category": {"projections": [{
        "field": {"Column": {"Expression": {"SourceRef": {"Entity": "List Date"}},
                             "Property": "Month Commencing Date"}},
        "queryRef": "List Date.Month Commencing Date",
        "nativeQueryRef": "Month Commencing Date"}]},
    "Y": {"projections": [meas("Total Revenue Indexed"),
                          meas("Private Revenue Indexed"),
                          meas("Plan Capitation Revenue Indexed")]},
}}
v["visual"].setdefault("visualContainerObjects", {})["title"] = [
    {"properties": {"text": {"expr": {"Literal": {"Value":
        "'Revenue mix, indexed to 100 a year ago -- plan up, private down, total flat'"}}}}}]
v.pop("filterConfig", None)

# ==> STRIP SELECTORS THAT NAME FIELDS THIS VISUAL NO LONGER QUERIES. <== A columnWidth left
# pointing at the template's own column is what stopped the Patient report loading entirely --
# not one broken visual, the whole report.
refs = {p["queryRef"] for b in v["visual"]["query"]["queryState"].values() for p in b["projections"]}
objs = v["visual"].get("objects", {}) or {}
for key in list(objs):
    kept = [o for o in (objs[key] or [])
            if not ((o.get("selector") or {}).get("metadata")
                    and (o.get("selector") or {}).get("metadata") not in refs)]
    if kept:
        objs[key] = kept
    else:
        objs.pop(key)
v["visual"]["objects"] = objs
v["isHidden"] = True
write(VIS / MIX / "visual.json", v)

# ── bookmarks ────────────────────────────────────────────────────────────────────────────
existing = sorted(BM.glob("*.bookmark.json"))
first = json.loads(existing[0].read_text(encoding="utf-8"))
targets = list(first["options"]["targetVisualNames"])
if MIX not in targets:
    targets.append(MIX)

types = {MIX: "lineChart"}
for d in VIS.iterdir():
    f = d / "visual.json"
    if f.exists():
        types.setdefault(d.name, json.loads(f.read_text(encoding="utf-8"))["visual"]["visualType"])

for f in existing:
    b = json.loads(f.read_text(encoding="utf-8"))
    b["options"]["targetVisualNames"] = targets
    b["explorationState"]["sections"][PAGE]["visualContainers"][MIX] = {
        "singleVisual": {"visualType": "lineChart", "objects": {}, "display": {"mode": "hidden"}}}
    write(f, b)
    print("   hid the new visual in %s" % b.get("displayName"))

vcs = {}
for n in targets:
    e = {"visualType": types.get(n, "columnChart"), "objects": {}}
    if n != MIX:
        e["display"] = {"mode": "hidden"}
    vcs[n] = {"singleVisual": e}
write(BM / ("%s.bookmark.json" % BM_MIX), {
    "$schema": first["$schema"], "displayName": "Revenue Mix", "name": BM_MIX,
    "options": {"applyOnlyToTargetVisuals": True, "targetVisualNames": targets,
                "suppressData": True},
    "explorationState": {"version": "1.0", "activeSection": PAGE,
                         "sections": {PAGE: {"visualContainers": vcs}}}})

meta = json.loads((BM / "bookmarks.json").read_text(encoding="utf-8"))
if not any(i["name"] == BM_MIX for i in meta["items"]):
    meta["items"].append({"name": BM_MIX})
write(BM / "bookmarks.json", meta)
print("\n   created bookmark 'Revenue Mix'; %d bookmarks now" % len(meta["items"]))
print("   visual %s: %s" % (MIX, [p["queryRef"] for p in
                                  v["visual"]["query"]["queryState"]["Y"]["projections"]]))
