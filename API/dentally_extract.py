"""
dentally_extract.py  --  Real Dentally extractor (token from Key Vault).

Reads dentally-tokens-<env> from Key Vault (one entry per Tenant_ID), then pulls each
practice's entities from the real api.dentally.co -- paginated, rate-aware, appointments
via the after/before window -- stamps every row with the Tenant_ID, and writes raw JSON
per entity to API/dentally_data/<tenant>/ (gitignored) for reconciliation against the
warehouse's expected fields. Same auth the production Fabric notebook will use.

  KV secret dentally-tokens-<env> = {"100": {"token": "...", "base_url": "...", "name": "..."}}

Usage:  python API/dentally_extract.py            (SAMPLE: reference full + few pages each)
        python API/dentally_extract.py --full     (FULL pull -- long + rate-limited)
Env:    DENTALLY_ENV (dev|prod, default dev), DENTALLY_KEYVAULT_URL (default kv-analytically).
"""
import argparse
import json
import os
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "dentally_data")
PER_PAGE = 100
KV_URL = os.environ.get("DENTALLY_KEYVAULT_URL", "https://kv-analytically.vault.azure.net/")
ENV    = os.environ.get("DENTALLY_ENV", "dev")

# Small reference sets -> always pulled in full. Big transactional sets -> sampled unless --full.
REFERENCE     = ["sites", "users", "practitioners", "treatments", "treatment_categories",
                 "payment_plans", "contracts"]
TRANSACTIONAL = ["patients", "invoices", "invoice_items", "treatment_plans",
                 "treatment_plan_items", "payments"]
APPT_WINDOW   = {"after": "2022-01-01T00:00:00Z", "before": "2027-01-01T00:00:00Z"}


def kv_tokens():
    from azure.identity import DefaultAzureCredential
    from azure.keyvault.secrets import SecretClient
    sc = SecretClient(vault_url=KV_URL, credential=DefaultAzureCredential())
    raw = (sc.get_secret(f"dentally-tokens-{ENV}").value or "").lstrip("﻿").strip()
    return json.loads(raw) if raw else {}


def req(base, headers, path, params):
    """GET with 429 backoff + a pause when the rate budget runs low."""
    for _ in range(6):
        r = requests.get(base + path, headers=headers, params=params, timeout=60)
        if r.status_code == 429:
            wait = int(r.headers.get("Retry-After", 30)) + 1
            print(f"    429 rate-limited; sleeping {wait}s")
            time.sleep(wait)
            continue
        r.raise_for_status()
        rem = r.headers.get("RateLimit-Remaining") or r.headers.get("X-RateLimit-Remaining")
        if rem and rem.isdigit() and int(rem) < 50:
            print(f"    rate budget low ({rem}); pausing 20s")
            time.sleep(20)
        return r
    raise RuntimeError("rate-limited repeatedly on " + path)


def fetch_all(base, headers, ep, params=None, max_pages=None):
    """Walk Dentally's page/per_page pagination. Terminates on a SHORT page (fewer than
    per_page rows = last page) -- NOT meta.total_pages, which some endpoints (patients/
    treatment_plan_items/payments) omit, so it defaulted to 1 and stopped after page 1.
    max_pages caps a sample."""
    out, page = [], 1
    while True:
        r = req(base, headers, "/" + ep, dict(params or {}, page=page, per_page=PER_PAGE))
        rows = next((v for k, v in r.json().items() if k != "meta"), [])
        if isinstance(rows, dict):
            rows = [rows]
        out.extend(rows)
        if len(rows) < PER_PAGE or (max_pages and page >= max_pages):
            return out
        page += 1


def save(outdir, name, rows):
    with open(os.path.join(outdir, name + ".json"), "w") as f:
        json.dump(rows, f, indent=2)


def stamp(rows, tid):
    for r in rows:
        if isinstance(r, dict):
            r["tenant_id"] = tid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--full", action="store_true", help="full pull (default: sample)")
    ap.add_argument("--sample-pages", type=int, default=3, help="pages/entity in sample mode")
    args = ap.parse_args()
    cap = None if args.full else args.sample_pages

    tokens = kv_tokens()
    if not tokens:
        raise SystemExit(f"dentally-tokens-{ENV} is empty/missing -- load the token into Key Vault first.")

    mode = "FULL" if args.full else f"SAMPLE ({args.sample_pages} pages/entity)"
    print(f"Env {ENV}  mode {mode}\n")
    for tid, cfg in tokens.items():
        base    = cfg.get("base_url", "https://api.dentally.co/v1").rstrip("/")
        headers = {"Authorization": "Bearer " + cfg["token"], "Accept": "application/json"}
        outdir  = os.path.join(DATA, str(tid))
        os.makedirs(outdir, exist_ok=True)
        print(f"Tenant {tid} ({cfg.get('name', '')}) @ {base}")

        r = req(base, headers, "/practice", {})
        practice = next((v for k, v in r.json().items() if k != "meta"), {})
        practice["tenant_id"] = tid
        save(outdir, "practice", [practice])
        print("  practice: 1")

        for ep in REFERENCE:
            rows = fetch_all(base, headers, ep)            # reference: always full
            stamp(rows, tid); save(outdir, ep, rows)
            print(f"  {ep}: {len(rows)}")

        appts = fetch_all(base, headers, "appointments", APPT_WINDOW, max_pages=cap)
        stamp(appts, tid); save(outdir, "appointments", appts)
        print(f"  appointments: {len(appts)}")

        for ep in TRANSACTIONAL:
            rows = fetch_all(base, headers, ep, max_pages=cap)
            stamp(rows, tid); save(outdir, ep, rows)
            print(f"  {ep}: {len(rows)}")

    print(f"\nDone. Raw per-tenant JSON in {DATA}")


if __name__ == "__main__":
    main()
