"""
dentally_audit_transform_bronze.py  --  read-only static audit.

For every entity: apply the REAL ingest transform (from build_Ingest_Dentally.py) to the
local T100 sample, collect the post-transform key set (= what lands in stage_<name>), then
extract the lowercase source columns the matching Bronze.usp_Load_*.sql reads FROM Stage.<X>,
and diff. A column Bronze READS but the transform does NOT EMIT = a silent-NULL bug for real
tenants (exactly the appointment-site + practitioner-user_* cases).

Usage:  python API/dentally_audit_transform_bronze.py
"""
import glob
import importlib.util
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(HERE, "dentally_data", "100")
FAB = os.path.join(ROOT, "Fabric")

# --- pull REGISTRY + transforms out of the notebook builder (authoritative source) --------
spec = importlib.util.spec_from_file_location(
    "bld", os.path.join(FAB, "Notebooks", "build_Ingest_Dentally.py"))
bld = importlib.util.module_from_spec(spec); spec.loader.exec_module(bld)
ns = {"json": json}
for src, _ in bld.CELLS:                       # exec the transforms cell then the registry cell
    if "def t_practitioner" in src or "REGISTRY = [" in src:
        exec(src, ns)
REGISTRY = ns["REGISTRY"] + [("fees", "fees", "ref", ns["passthrough"])]

# --- map a stage table name -> its Bronze loader file --------------------------------------
bronze_files = glob.glob(os.path.join(FAB, "Bronze.usp_Load_*.StoredProcedure.sql"))
def norm(s): return s.lower().replace("_", "")
bronze_by_norm = {norm(os.path.basename(f).split(".")[1].replace("usp_Load_", "")): f
                  for f in bronze_files}

SQL_WORDS = set("""as into from where and or case when then else end null is not in on select
distinct group by order having over partition asc desc cross apply join inner outer set begin
try catch left right cast try_cast convert isnull coalesce nullif lower upper trim ltrim rtrim
round floor ceiling abs concat concat_ws hashbytes len replace substring iif sysutcdatetime
getdate int bigint float double real decimal numeric money smallint tinyint bit varchar nvarchar
char nchar datetime datetime2 date time varbinary max sha2_256 src tgt staged stage a r u""".split())

def bronze_stage_cols(path):
    txt = open(path, encoding="utf-8-sig", errors="ignore").read()
    # the first SELECT ... INTO #src ... FROM Stage.<X> block
    m = re.search(r"\bSELECT\b(.*?)\bINTO\s+#src\b", txt, re.S | re.I)
    seg = m.group(1) if m else ""
    seg = re.sub(r"'[^']*'", "", seg)          # strip SQL string literals ('true','1',...)
    toks = set(re.findall(r"\b([a-z][a-z0-9_]*)\b", seg))
    return {t for t in toks if t not in SQL_WORDS}

# --- run the audit -------------------------------------------------------------------------
def load_sample(ep):
    p = os.path.join(DATA, ep + ".json")
    if not os.path.exists(p):
        return None
    rows = json.load(open(p))
    return rows if isinstance(rows, list) else [rows]

print("entity                     | bronze | emit | MISSING (bronze reads, transform omits)")
print("-" * 100)
seen_children = {}
for ep, stage_name, kind, fn in REGISTRY:
    rows = load_sample(ep)
    if not rows:
        print("%-26s | (no sample)" % stage_name)
        continue
    emitted, children = set(), {}
    for r in rows:
        main, ch = fn(r)
        emitted.update(main.keys())
        for cn, crows in ch.items():
            children.setdefault(cn, set())
            for cr in crows:
                children[cn].update(cr.keys())
    emitted |= {"tenant_id", "dw_stage_loaded_at"}   # write_stage stamps these
    seen_children.update(children)

    bf = bronze_by_norm.get(norm(stage_name))
    if not bf:
        print("%-26s | (no Bronze.usp_Load_%s)" % (stage_name, stage_name))
        continue
    reads = bronze_stage_cols(bf)
    raw_keys = {k.lower() for r in rows for k in r.keys()}
    missing = sorted(reads - {e.lower() for e in emitted})
    # annotate: [raw] = in the real API record but we dropped/renamed it (OUR bug);
    #           [absent] = not in the real API at all (mock-ism -> always NULL for real).
    ann = ["%s[%s]" % (c, "raw" if c in raw_keys else "absent") for c in missing]
    flag = "  <== CHECK" if missing else ""
    print("%-26s | %5d  | %4d | %s%s" % (stage_name, len(reads), len(emitted),
                                         ", ".join(ann) if ann else "(clean)", flag))

# child stage tables (payment_explanations, practitioner_diary_breaks)
for cn, keys in seen_children.items():
    bf = bronze_by_norm.get(norm(cn))
    keys |= {"tenant_id", "dw_stage_loaded_at"}
    if not bf:
        print("%-26s | (child; no Bronze.usp_Load_%s)" % (cn, cn))
        continue
    reads = bronze_stage_cols(bf)
    missing = sorted(reads - {k.lower() for k in keys})
    print("%-26s | %5d  | %4d | %s  <child>" % (cn, len(reads), len(keys),
                                                ", ".join(missing) if missing else "(clean)"))
