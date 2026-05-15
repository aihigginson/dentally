"""
Dentally Mock API
-----------------
Serves pre-generated test data from API/data/tenant_{1-4}.json.
Run generate_data.py once first to produce the data files.

Multi-tenant:
    Tenant 1 -- Smile Group (Oxford)          Bearer dev-mock-key-abc123
    Tenant 2 -- Bright Dental (Brighton)      Bearer dev-mock-key-tenant2
    Tenant 3 -- ClearSmile Manchester         Bearer dev-mock-key-tenant3
    Tenant 4 -- ClearSmile Birmingham         Bearer dev-mock-key-tenant4
    Patient / appointment IDs overlap between tenants intentionally,
    to verify that Tenant_ID isolation in the ETL is working correctly.

Usage:
    python API/mock_api.py  ->  http://localhost:5000

Endpoints (all tenants):
    GET /v1/practice
    GET /v1/sites
    GET /v1/users
    GET /v1/practitioners              ?site_id=
    GET /v1/payment_plans
    GET /v1/treatments
    GET /v1/treatment_categories
    GET /v1/acquisition_sources
    GET /v1/cancellation_reasons
    GET /v1/waiting_lists              ?site_id=
    GET /v1/sundries                   ?site_id=
    GET /v1/contracts                  ?site_id=
    GET /v1/fees                       ?payment_plan_id=  &treatment_id=
    GET /v1/patients                   ?site_id=  &active=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/patients/{id}
    GET /v1/accounts                   ?patient_id=  &page=  &per_page=
    GET /v1/patient_stats              ?patient_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/appointments               ?site_id=  &practitioner_id=  &patient_id=  &state=
                                       &after=YYYY-MM-DD  &before=YYYY-MM-DD  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/treatment_appointments     ?patient_id=  &treatment_plan_id=  &appointment_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/invoices                   ?site_id=  &patient_id=  &dated_after=  &dated_before=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/invoice_items              ?invoice_id=  &patient_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/payments                   ?site_id=  &patient_id=  &dated_after=  &dated_before=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/payment_explanations       ?payment_id=  &page=  &per_page=
    GET /v1/payment_allocations        ?patient_id=  &invoice_item_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/treatment_plans            ?site_id=  &patient_id=  &completed=  &created_after=  &created_before=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/treatment_plan_items       ?treatment_plan_id=  &patient_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/recalls                    ?site_id=  &patient_id=  &practitioner_id=  &overdue=true  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/nhs_claims                 ?patient_id=  &contract_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/practitioner_diary_entries ?practitioner_id=  &site_id=  &date_after=  &date_before=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/practitioner_diary_breaks  ?practitioner_diary_id=  &page=  &per_page=
"""

import json
import math
import os
import random
from pathlib import Path

from flask import Flask, g, jsonify, request

app = Flask(__name__)

# ==============================================================================
# LOAD DATA FILES AT STARTUP
# ==============================================================================

API_KEYS = [
    "dev-mock-key-abc123",
    "dev-mock-key-tenant2",
    "dev-mock-key-tenant3",
    "dev-mock-key-tenant4",
]
ALL_KEYS = set(API_KEYS)

# Support DENTALLY_API_KEY override for Tenant 1 (backwards compat)
_env_key = os.environ.get("DENTALLY_API_KEY")
if _env_key and _env_key != API_KEYS[0]:
    ALL_KEYS.add(_env_key)

_data_dir = Path(__file__).parent / "data"

print("Loading tenant data from JSON files...")

TENANT_DATA = {}
_tenant_names = {}

for _idx, _key in enumerate(API_KEYS, 1):
    _path = _data_dir / f"tenant_{_idx}.json"
    if not _path.exists():
        print(f"  WARNING: {_path} not found. Run generate_data.py first.")
        continue
    with open(_path, "r", encoding="utf-8") as _f:
        _tdata = json.load(_f)
    TENANT_DATA[_key] = _tdata
    _tenant_names[_key] = _tdata.get("practice", {}).get("name", f"Tenant {_idx}")
    _n_patients = len(_tdata.get("patients", []))
    _n_apts = len(_tdata.get("appointments", []))
    _n_inv = len(_tdata.get("invoices", []))
    _n_claims = len(_tdata.get("nhs_claims", []))
    print(f"  Tenant {_idx} -- {_tenant_names[_key]}: "
          f"{_n_patients} patients  {_n_apts} appointments  "
          f"{_n_inv} invoices  {_n_claims} NHS claims")

# Support DENTALLY_API_KEY override: alias Tenant 1 data under env key
if _env_key and _env_key != API_KEYS[0] and API_KEYS[0] in TENANT_DATA:
    TENANT_DATA[_env_key] = TENANT_DATA[API_KEYS[0]]
    _tenant_names[_env_key] = _tenant_names[API_KEYS[0]]

print()


# ==============================================================================
# AUTH
# ==============================================================================

@app.before_request
def check_auth():
    if request.path == "/":
        return None
    key = request.headers.get("Authorization", "").removeprefix("Bearer ")
    if key not in ALL_KEYS or key not in TENANT_DATA:
        return jsonify({"error": "Unauthorized"}), 401
    g.data = TENANT_DATA[key]


# ==============================================================================
# HELPERS
# ==============================================================================

def paginate(items):
    page = int(request.args.get("page", 1))
    per_page = min(int(request.args.get("per_page", 25)), 100)
    total = len(items)
    start = (page - 1) * per_page
    return (
        items[start: start + per_page],
        {
            "total": total,
            "current_page": page,
            "total_pages": math.ceil(total / per_page) if total else 0,
        },
    )


def filter_updated_after(items):
    v = request.args.get("updated_after")
    if not v:
        return items
    return [i for i in items if i.get("updated_at", "") >= v]


def add_cors(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    return response


app.after_request(add_cors)


# ==============================================================================
# ROUTES -- REFERENCE DATA
# ==============================================================================

@app.route("/v1/practice")
def practice():
    return jsonify({"practice": g.data["practice"]})


@app.route("/v1/sites")
def sites():
    s = g.data["sites"]
    return jsonify({"sites": s, "meta": {"total": len(s), "current_page": 1, "total_pages": 1}})


@app.route("/v1/users")
def users():
    page_data, meta = paginate(g.data["users"])
    return jsonify({"users": page_data, "meta": meta})


@app.route("/v1/practitioners")
def practitioners():
    result = list(g.data["practitioners"])
    if sid := request.args.get("site_id"):
        result = [p for p in result if p["site_id"] == sid]
    page_data, meta = paginate(result)
    return jsonify({"practitioners": page_data, "meta": meta})


@app.route("/v1/payment_plans")
def payment_plans():
    pp = g.data["payment_plans"]
    return jsonify({"payment_plans": pp, "meta": {"total": len(pp), "current_page": 1, "total_pages": 1}})


@app.route("/v1/treatments")
def treatments():
    items = g.data["treatments"]
    return jsonify({"treatments": items, "meta": {"total": len(items), "current_page": 1, "total_pages": 1}})


@app.route("/v1/treatment_categories")
def treatment_categories():
    page_data, meta = paginate(g.data["treatment_categories"])
    return jsonify({"treatment_categories": page_data, "meta": meta})


@app.route("/v1/acquisition_sources")
def acquisition_sources():
    page_data, meta = paginate(g.data["acquisition_sources"])
    return jsonify({"acquisition_sources": page_data, "meta": meta})


@app.route("/v1/cancellation_reasons")
def cancellation_reasons():
    page_data, meta = paginate(g.data["cancellation_reasons"])
    return jsonify({"cancellation_reasons": page_data, "meta": meta})


@app.route("/v1/waiting_lists")
def waiting_lists():
    result = list(g.data["waiting_lists"])
    if v := request.args.get("site_id"):
        result = [w for w in result if w["site_id"] == v]
    page_data, meta = paginate(result)
    return jsonify({"waiting_lists": page_data, "meta": meta})


@app.route("/v1/sundries")
def sundries():
    result = list(g.data["sundries"])
    if v := request.args.get("site_id"):
        result = [s for s in result if s["site_id"] == v]
    page_data, meta = paginate(result)
    return jsonify({"sundries": page_data, "meta": meta})


@app.route("/v1/contracts")
def contracts():
    result = list(g.data["contracts"])
    if v := request.args.get("site_id"):
        result = [c for c in result if c["site_id"] == v]
    page_data, meta = paginate(result)
    return jsonify({"contracts": page_data, "meta": meta})


@app.route("/v1/fees")
def fees():
    result = list(g.data["fees"])
    if v := request.args.get("payment_plan_id"):
        result = [f for f in result if str(f["payment_plan_id"]) == v]
    if v := request.args.get("treatment_id"):
        result = [f for f in result if str(f["treatment_id"]) == v]
    page_data, meta = paginate(result)
    return jsonify({"fees": page_data, "meta": meta})


@app.route("/v1/practitioner_diary_breaks")
def diary_breaks():
    result = list(g.data["diary_breaks"])
    if v := request.args.get("practitioner_diary_id"):
        result = [b for b in result if str(b["practitioner_diary_id"]) == v]
    page_data, meta = paginate(result)
    return jsonify({"practitioner_diary_breaks": page_data, "meta": meta})


# ==============================================================================
# ROUTES -- PATIENTS & ACCOUNTS
# ==============================================================================

@app.route("/v1/patients")
def patients():
    result = list(g.data["patients"])
    if v := request.args.get("site_id"):
        result = [p for p in result if p["site_id"] == v]
    if v := request.args.get("active"):
        result = [p for p in result if str(p["active"]).lower() == v.lower()]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"patients": page_data, "meta": meta})


@app.route("/v1/patients/<int:patient_id>")
def patient(patient_id):
    p = next((p for p in g.data["patients"] if p["id"] == patient_id), None)
    if not p:
        return jsonify({"error": "Patient not found"}), 404
    return jsonify({"patient": p})


@app.route("/v1/accounts")
def accounts():
    data = g.data
    plan_map = {pp["id"]: pp for pp in data["payment_plans"]}
    inv_by_pat = {}
    for i in data["invoices"]:
        inv_by_pat.setdefault(i["patient_id"], []).append(i)
    plan_by_pat = {}
    for pl in data["treatment_plans"]:
        plan_by_pat.setdefault(pl["patient_id"], []).append(pl)
    result = []
    for p in data["patients"]:
        inv = inv_by_pat.get(p["id"], [])
        outstanding = sum(float(i["amount_outstanding"]) for i in inv)
        pp = plan_map.get(p["payment_plan_id"], {})
        open_plans = [pl for pl in plan_by_pat.get(p["id"], []) if not pl.get("completed")]
        nhs_val = sum(float(pl.get("nhs_uda_value") or 0) for pl in open_plans) if pp.get("nhs") else 0.0
        priv_val = sum(float(pl.get("private_treatment_value") or 0) for pl in open_plans) if not pp.get("nhs") else 0.0
        result.append({
            "id": p["account_id"],
            "patient_id": p["id"],
            "patient_name": f"{p['first_name']} {p['last_name']}",
            "current_balance": f"{-outstanding:.2f}",
            "opening_balance": "0.00",
            "planned_nhs_treatment_value": f"{nhs_val:.2f}",
            "planned_private_treatment_value": f"{priv_val:.2f}",
        })
    if pid := request.args.get("patient_id"):
        result = [a for a in result if str(a["patient_id"]) == pid]
    page_data, meta = paginate(result)
    return jsonify({"accounts": page_data, "meta": meta})


@app.route("/v1/patient_stats")
def patient_stats():
    result = list(g.data["patient_stats"])
    if v := request.args.get("patient_id"):
        result = [s for s in result if str(s["patient_id"]) == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"patient_stats": page_data, "meta": meta})


# ==============================================================================
# ROUTES -- APPOINTMENTS
# ==============================================================================

@app.route("/v1/appointments")
def appointments():
    result = list(g.data["appointments"])
    if v := request.args.get("practitioner_id"):
        result = [a for a in result if str(a["practitioner_id"]) == v]
    if v := request.args.get("patient_id"):
        result = [a for a in result if str(a["patient_id"]) == v]
    if v := request.args.get("site_id"):
        result = [a for a in result if a["site_id"] == v]
    if v := request.args.get("state"):
        result = [a for a in result if a["state"].lower() == v.lower()]
    if v := request.args.get("after"):
        result = [a for a in result if a["start_time"][:10] >= v]
    if v := request.args.get("before"):
        result = [a for a in result if a["start_time"][:10] <= v]
    result = filter_updated_after(result)
    result.sort(key=lambda a: a["start_time"])
    page_data, meta = paginate(result)
    return jsonify({"appointments": page_data, "meta": meta})


@app.route("/v1/treatment_appointments")
def treatment_appointments_route():
    result = list(g.data["treatment_appts"])
    if v := request.args.get("patient_id"):
        result = [t for t in result if str(t["patient_id"]) == v]
    if v := request.args.get("treatment_plan_id"):
        result = [t for t in result if str(t["treatment_plan_id"]) == v]
    if v := request.args.get("appointment_id"):
        result = [t for t in result if str(t["appointment_id"]) == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"treatment_appointments": page_data, "meta": meta})


# ==============================================================================
# ROUTES -- INVOICES & PAYMENTS
# ==============================================================================

@app.route("/v1/invoices")
def invoices():
    result = list(g.data["invoices"])
    if v := request.args.get("patient_id"):
        result = [i for i in result if str(i["patient_id"]) == v]
    if v := request.args.get("site_id"):
        result = [i for i in result if i["site_id"] == v]
    if v := request.args.get("dated_after"):
        result = [i for i in result if i["dated_on"] >= v]
    if v := request.args.get("dated_before"):
        result = [i for i in result if i["dated_on"] <= v]
    result = filter_updated_after(result)
    result.sort(key=lambda i: i["dated_on"])
    page_data, meta = paginate(result)
    return jsonify({"invoices": page_data, "meta": meta})


@app.route("/v1/invoice_items")
def invoice_items():
    result = list(g.data["invoice_items"])
    if v := request.args.get("invoice_id"):
        result = [i for i in result if str(i["invoice_id"]) == v]
    if v := request.args.get("patient_id"):
        result = [i for i in result if str(i["patient_id"]) == v]
    if v := request.args.get("site_id"):
        result = [i for i in result if i["site_id"] == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"invoice_items": page_data, "meta": meta})


@app.route("/v1/payments")
def payments():
    result = list(g.data["payments"])
    if v := request.args.get("patient_id"):
        result = [p for p in result if str(p["patient_id"]) == v]
    if v := request.args.get("site_id"):
        result = [p for p in result if p["site_id"] == v]
    if v := request.args.get("dated_after"):
        result = [p for p in result if p["dated_on"] >= v]
    if v := request.args.get("dated_before"):
        result = [p for p in result if p["dated_on"] <= v]
    result = filter_updated_after(result)
    result.sort(key=lambda p: p["dated_on"])
    page_data, meta = paginate(result)
    total_value = sum(float(p["amount"]) for p in result)
    meta["total_payments_value"] = f"{total_value:.2f}"
    return jsonify({"payments": page_data, "meta": meta})


@app.route("/v1/payment_explanations")
def payment_explanations():
    result = list(g.data["payment_explanations"])
    if v := request.args.get("payment_id"):
        result = [e for e in result if str(e["payment_id"]) == v]
    page_data, meta = paginate(result)
    return jsonify({"payment_explanations": page_data, "meta": meta})


@app.route("/v1/payment_allocations")
def payment_allocations():
    result = list(g.data["payment_allocations"])
    if v := request.args.get("patient_id"):
        result = [a for a in result if str(a["patient_id"]) == v]
    if v := request.args.get("invoice_item_id"):
        result = [a for a in result if a["invoice_item_id"] == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"payment_allocations": page_data, "meta": meta})


# ==============================================================================
# ROUTES -- TREATMENT PLANS
# ==============================================================================

@app.route("/v1/treatment_plans")
def treatment_plans():
    result = list(g.data["treatment_plans"])
    if v := request.args.get("patient_id"):
        result = [t for t in result if str(t["patient_id"]) == v]
    if v := request.args.get("site_id"):
        result = [t for t in result if t["site_id"] == v]
    if v := request.args.get("created_after"):
        result = [t for t in result if t["created_at"][:10] >= v]
    if v := request.args.get("created_before"):
        result = [t for t in result if t["created_at"][:10] <= v]
    if v := request.args.get("completed"):
        flag = v.lower() == "true"
        result = [t for t in result if bool(t.get("completed")) == flag]
    result = filter_updated_after(result)
    result.sort(key=lambda t: t["created_at"])
    page_data, meta = paginate(result)
    return jsonify({"treatment_plans": page_data, "meta": meta})


@app.route("/v1/treatment_plan_items")
def treatment_plan_items():
    result = list(g.data["treatment_plan_items"])
    if v := request.args.get("treatment_plan_id"):
        result = [i for i in result if str(i["treatment_plan_id"]) == v]
    if v := request.args.get("patient_id"):
        result = [i for i in result if str(i["patient_id"]) == v]
    if v := request.args.get("site_id"):
        result = [i for i in result if i["site_id"] == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"treatment_plan_items": page_data, "meta": meta})


# ==============================================================================
# ROUTES -- RECALLS
# ==============================================================================

@app.route("/v1/recalls")
def recalls():
    result = list(g.data["recalls"])
    if v := request.args.get("patient_id"):
        result = [r for r in result if str(r["patient_id"]) == v]
    if v := request.args.get("site_id"):
        result = [r for r in result if r["site_id"] == v]
    if v := request.args.get("practitioner_id"):
        result = [r for r in result if str(r["practitioner_id"]) == v]
    if request.args.get("overdue") == "true":
        from datetime import date
        today = str(date.today())
        result = [r for r in result if r.get("recall_date", "9999") < today and r.get("status") != "complete"]
    result = filter_updated_after(result)
    result.sort(key=lambda r: r.get("recall_date", ""))
    page_data, meta = paginate(result)
    return jsonify({"recalls": page_data, "meta": meta})


# ==============================================================================
# ROUTES -- NHS CLAIMS & PRACTITIONER DIARIES
# ==============================================================================

@app.route("/v1/nhs_claims")
def nhs_claims():
    result = list(g.data["nhs_claims"])
    if v := request.args.get("patient_id"):
        result = [c for c in result if str(c["patient_id"]) == v]
    if v := request.args.get("contract_id"):
        result = [c for c in result if c["contract_id"] == v]
    if v := request.args.get("site_id"):
        result = [c for c in result if c["site_id"] == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"nhs_claims": page_data, "meta": meta})


@app.route("/v1/practitioner_diary_entries")
def diary_entries():
    result = list(g.data["diary_entries"])
    if v := request.args.get("practitioner_id"):
        result = [d for d in result if str(d["practitioner_id"]) == v]
    if v := request.args.get("site_id"):
        result = [d for d in result if d["site_id"] == v]
    if v := request.args.get("date_after"):
        result = [d for d in result if d["date"] >= v]
    if v := request.args.get("date_before"):
        result = [d for d in result if d["date"] <= v]
    result = filter_updated_after(result)
    result.sort(key=lambda d: d["start_time"])
    page_data, meta = paginate(result)
    return jsonify({"practitioner_diary_entries": page_data, "meta": meta})


# ==============================================================================
# ROOT -- ENDPOINT INDEX
# ==============================================================================

@app.route("/")
def index():
    tenants = {
        _tenant_names.get(k, k): f"Bearer {k}"
        for k in API_KEYS
        if k in TENANT_DATA
    }
    return jsonify({
        "name": "Dentally Mock API",
        "version": "v1",
        "tenants": tenants,
        "endpoints": {
            "reference": [
                "GET /v1/practice",
                "GET /v1/sites",
                "GET /v1/users",
                "GET /v1/practitioners              ?site_id=",
                "GET /v1/payment_plans",
                "GET /v1/treatments",
                "GET /v1/treatment_categories",
                "GET /v1/acquisition_sources",
                "GET /v1/cancellation_reasons",
                "GET /v1/waiting_lists              ?site_id=",
                "GET /v1/sundries                   ?site_id=",
                "GET /v1/contracts                  ?site_id=",
                "GET /v1/fees                       ?payment_plan_id=  &treatment_id=",
                "GET /v1/practitioner_diary_breaks  ?practitioner_diary_id=",
            ],
            "patients": [
                "GET /v1/patients                   ?site_id=  &active=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/patients/{id}",
                "GET /v1/accounts                   ?patient_id=  &page=  &per_page=",
                "GET /v1/patient_stats              ?patient_id=  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "appointments": [
                "GET /v1/appointments               ?site_id=  &practitioner_id=  &patient_id=  &state=  &after=YYYY-MM-DD  &before=YYYY-MM-DD  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/treatment_appointments     ?patient_id=  &treatment_plan_id=  &appointment_id=  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "invoices_and_payments": [
                "GET /v1/invoices                   ?site_id=  &patient_id=  &dated_after=  &dated_before=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/invoice_items              ?invoice_id=  &patient_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/payments                   ?site_id=  &patient_id=  &dated_after=  &dated_before=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/payment_explanations       ?payment_id=  &page=  &per_page=",
                "GET /v1/payment_allocations        ?patient_id=  &invoice_item_id=  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "treatment_plans": [
                "GET /v1/treatment_plans            ?site_id=  &patient_id=  &completed=  &created_after=  &created_before=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/treatment_plan_items       ?treatment_plan_id=  &patient_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "recalls": [
                "GET /v1/recalls                    ?site_id=  &patient_id=  &practitioner_id=  &overdue=true  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "nhs": [
                "GET /v1/nhs_claims                 ?patient_id=  &contract_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "diaries": [
                "GET /v1/practitioner_diary_entries ?practitioner_id=  &site_id=  &date_after=  &date_before=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/practitioner_diary_breaks  ?practitioner_diary_id=  &page=  &per_page=",
            ],
        },
        "pagination": "All list endpoints support ?page= (default 1) and ?per_page= (default 25, max 100)",
        "note": "Pre-generated test data served from JSON files. Run generate_data.py to regenerate.",
    })


if __name__ == "__main__":
    print("Dentally Mock API  ->  http://localhost:5000")
    print("Endpoint index     ->  http://localhost:5000/\n")
    app.run(host="0.0.0.0", port=5000, debug=False)
