"""
dentally_transform.py  --  Real Dentally record -> stage-shaped record(s).

The flatten/drop/fix layer from DENTALLY_RECONCILIATION.md, isolated so it can be
VALIDATED locally against the real sample files before it's ported into the Fabric
Ingest_Dentally notebook. Each transform takes a raw API record and returns
(main_record, {child_stage_name: [child_records]}) -- children cover the nested arrays
Dentally embeds that the warehouse wants as their own stage tables.

Run:  python API/dentally_transform.py   (reads dentally_data/<tenant>/*.json, writes
      dentally_data/<tenant>/stage/stage_*.json, prints a summary to eyeball)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "dentally_data")

# Special-category / PII to NEVER land (DPIA V011/V012). Patients.
PII_DROP = {
    "date_of_birth", "gender", "ethnicity", "nhs_number", "ni_number", "pps_number",
    "medical_alert", "medical_alert_text", "special_needs", "occupation", "school_name",
    "emergency_contact_name", "emergency_contact_phone", "emergency_contact_phone_country",
    "emergency_contact_phone_normalized", "emergency_contact_relationship",
    "proof_of_identification", "suspicious_identity", "image_url", "metadata",
}


def _drop(r, keys):
    return {k: v for k, v in r.items() if k not in keys}


def t_practitioner(r):
    # Flatten the nested user (name/email/ROLE) + drop the big nested user/site objects.
    u = r.get("user") or {}
    out = _drop(r, {"user", "site", "specialisms", "contract_targets"})
    out.update({
        "user_id":    u.get("id"),
        "first_name": u.get("first_name"), "middle_name": u.get("middle_name"),
        "last_name":  u.get("last_name"),  "email": u.get("email"),
        "role":       u.get("role"),       "permission_level": u.get("permission_level"),
    })
    return out, {}


def t_patient(r):
    # Drop special-category / PII; keep identity/contact/recall/assignment fields.
    return _drop(r, PII_DROP | {"custom_fields"}), {}


def t_payment(r):
    # Split the embedded explanations[] into their own stage (mock had them separate).
    exps = [dict(e, payment_id=r.get("id"), tenant_id=r.get("tenant_id"))
            for e in (r.get("explanations") or [])]
    return _drop(r, {"explanations"}), {"payment_explanations": exps}


def t_rota(r):
    # Split embedded breaks[] into their own stage; keep the day rota row.
    brks = [dict(b, rota_id=r.get("id"), practitioner_id=r.get("practitioner_id"),
                 day=r.get("day"), tenant_id=r.get("tenant_id"))
            for b in (r.get("breaks") or [])]
    return _drop(r, {"breaks"}), {"practitioner_diary_breaks": brks}


def t_tp_item(r):
    # Drop free-text clinical (notes); json-encode the small arrays for a string stage.
    out = _drop(r, {"notes", "custom_fields"})
    for k in ("teeth", "surfaces"):
        if isinstance(out.get(k), list):
            out[k] = json.dumps(out[k])
    return out, {}


def t_appointment(r):
    return _drop(r, {"notes", "metadata"}), {}


def passthrough(r):
    return r, {}


# entity file -> transform. Anything not listed passes through unchanged.
TRANSFORMS = {
    "practitioners": t_practitioner,
    "patients": t_patient,
    "payments": t_payment,
    "rota_practitioner_diaries": t_rota,
    "treatment_plan_items": t_tp_item,
    "appointments": t_appointment,
}


def transform_file(tenant_dir, name):
    path = os.path.join(tenant_dir, name + ".json")
    if not os.path.exists(path):
        return None
    rows = json.load(open(path))
    fn = TRANSFORMS.get(name, passthrough)
    main, children = [], {}
    for r in rows:
        m, ch = fn(r)
        main.append(m)
        for cname, crows in ch.items():
            children.setdefault(cname, []).extend(crows)
    return main, children


def main():
    tenant = sys.argv[1] if len(sys.argv) > 1 else "100"
    tdir = os.path.join(DATA, tenant)
    outdir = os.path.join(tdir, "stage")
    os.makedirs(outdir, exist_ok=True)
    entities = sorted(f[:-5] for f in os.listdir(tdir) if f.endswith(".json"))
    for name in entities:
        res = transform_file(tdir, name)
        if not res:
            continue
        main_rows, children = res
        json.dump(main_rows, open(os.path.join(outdir, "stage_" + name + ".json"), "w"), indent=2)
        fields = sorted(main_rows[0].keys()) if main_rows else []
        extra = "".join(f"  +{c}={len(v)}" for c, v in children.items())
        print(f"stage_{name:26} {len(main_rows):>4} rows, {len(fields)} cols{extra}")
        for cname, crows in children.items():
            json.dump(crows, open(os.path.join(outdir, "stage_" + cname + ".json"), "w"), indent=2)
    print(f"\nStage-shaped output -> {outdir}")


if __name__ == "__main__":
    main()
