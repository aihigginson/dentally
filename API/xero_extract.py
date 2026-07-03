"""
xero_extract.py  --  Production extract of the Xero profitability slice for every
connected organisation.

For each connection (OAuth consent) in the token store it refreshes the access token
(persisting the rotated refresh token), then for each mapped org pulls:
  - the chart of accounts (Accounts),
  - tracking categories (site split),
  - the FULL set (all pages) of P&L-affecting documents: invoices, credit notes,
    bank transactions, manual journals, payments,
  - the Profit & Loss report -- used only as a reconciliation check.

Raw JSON is written per-org to API/xero_data/<xero_tenant_id>/ (gitignored), with a
_meta.json recording the Dentally Tenant_ID + default site for the lander.

Snapshot semantics: a full pull each run (Bronze treats the stage as a snapshot).
Incremental (If-Modified-Since) is a deliberate future cost optimisation -- a single
practice's ledger is well inside Xero's 5,000-calls/day/org limit.

Uses only the standard granular scopes any connection can grant (invoices/
banktransactions/manualjournals/payments/settings/reports.profitandloss .read) --
NOT the gated accounting.journals.read.

Usage:  python API/xero_extract.py                 (all mapped orgs)
        python API/xero_extract.py <xeroTenantId>  (one org)
"""
import base64
import json
import os
import sys
import time
from collections import Counter
from datetime import date, timedelta

import requests

import xero_store as store

HERE      = os.path.dirname(os.path.abspath(__file__))
DATA_DIR  = os.path.join(HERE, "xero_data")
TOKEN_URL = "https://identity.xero.com/connect/token"
API_BASE  = "https://api.xero.com/api.xro/2.0"
PAGE_SIZE = 100          # Xero's fixed page size for paged endpoints
MAX_429   = 6            # give up after this many consecutive rate-limit waits

creds = store.load_creds()

# Paged P&L-affecting documents: (path, response key, saved name).
PAGED_DOCS = [
    ("/Invoices",         "Invoices",         "invoices"),
    ("/CreditNotes",      "CreditNotes",      "creditnotes"),
    ("/BankTransactions", "BankTransactions", "banktransactions"),
    ("/ManualJournals",   "ManualJournals",   "manualjournals"),
    ("/Payments",         "Payments",         "payments"),
]


def _basic():
    raw = f"{creds.XERO_CLIENT_ID}:{creds.XERO_CLIENT_SECRET}".encode()
    return "Basic " + base64.b64encode(raw).decode()


def refresh(blob):
    """Swap the refresh token for a fresh access token; the caller persists the blob
    afterwards (Xero rotates the refresh token on every use)."""
    r = requests.post(TOKEN_URL, headers={
        "Authorization": _basic(),
        "Content-Type":  "application/x-www-form-urlencoded",
    }, data={
        "grant_type":    "refresh_token",
        "refresh_token": blob["tokens"]["refresh_token"],
    })
    r.raise_for_status()
    blob["tokens"].update(r.json())
    return blob["tokens"]["access_token"]


def xget(path, access, tid, params=None):
    """GET one Xero page, backing off on HTTP 429 (honours Retry-After)."""
    for _ in range(MAX_429):
        r = requests.get(API_BASE + path, headers={
            "Authorization":  "Bearer " + access,
            "Xero-tenant-id": tid,
            "Accept":         "application/json",
        }, params=params or {})
        if r.status_code == 429:
            wait = int(r.headers.get("Retry-After", 5)) + 1
            print(f"      429 rate-limited; sleeping {wait}s")
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError(f"Rate-limited {MAX_429}x on {path}")


def xget_all(path, key, access, tid):
    """Follow Xero page-based pagination to pull EVERY page (the POC pulled page 1)."""
    out, page = [], 1
    while True:
        rows = xget(path, access, tid, {"page": page}).get(key, []) or []
        out.extend(rows)
        if len(rows) < PAGE_SIZE:
            return out
        page += 1


def save_json(org_dir, name, obj):
    d = os.path.join(DATA_DIR, org_dir)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name + ".json"), "w") as f:
        json.dump(obj, f, indent=2)


def print_pl(report):
    """Flatten the Xero P&L report rows into readable label: value lines."""
    def walk(rows, indent=0):
        for r in rows:
            rt = r.get("RowType")
            if rt == "Section":
                if r.get("Title"):
                    print("   " * indent + r["Title"])
                walk(r.get("Rows", []), indent + 1)
            elif rt in ("Row", "SummaryRow"):
                cells = r.get("Cells", [])
                if cells:
                    label = cells[0].get("Value", "")
                    value = cells[-1].get("Value", "") if len(cells) > 1 else ""
                    if label:
                        print("   " * indent + f"{label}: {value}")
    for section in report.get("Rows", []):
        walk([section])


def extract_org(access, tenant, tenant_id, default_site_id):
    tid = tenant["tenantId"]
    org_dir = tid

    save_json(org_dir, "_meta", {
        "tenant_id":        tenant_id,
        "xero_tenant_id":   tid,
        "tenant_name":      tenant.get("tenantName"),
        "default_site_id":  default_site_id,
    })

    accounts = xget("/Accounts", access, tid)["Accounts"]
    save_json(org_dir, "accounts", accounts)
    cls = Counter(a.get("Class", "?") for a in accounts)
    print(f"    Accounts: {len(accounts)}  ({', '.join(f'{k}:{n}' for k, n in cls.most_common())})")

    tracking = xget("/TrackingCategories", access, tid).get("TrackingCategories", []) or []
    save_json(org_dir, "tracking_categories", tracking)
    print(f"    Tracking categories: {len(tracking)}")

    for path, key, name in PAGED_DOCS:
        try:
            rows = xget_all(path, key, access, tid)
        except requests.HTTPError as e:
            print(f"    {key}: HTTP {e.response.status_code} (scope?) - skipped")
            continue
        save_json(org_dir, name, rows)
        print(f"    {key}: {len(rows)}")

    to_d, from_d = date.today(), date.today() - timedelta(days=365)
    pl = xget("/Reports/ProfitAndLoss", access, tid,
              {"fromDate": from_d.isoformat(), "toDate": to_d.isoformat()})
    save_json(org_dir, "profit_and_loss", pl)
    print(f"    P&L pulled ({from_d} to {to_d}) - reconciliation reference")


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    processed = 0
    for conn_key in store.list_connections():
        blob = store.load_connection(conn_key)
        access = refresh(blob)
        store.save_connection(conn_key, blob)   # persist the rotated refresh token
        for tenant in blob.get("tenants", []):
            if only and tenant["tenantId"] != only:
                continue
            org = store.resolve_org(creds, tenant)
            if not org:
                print(f"Skip unmapped org: {tenant.get('tenantName')} ({tenant['tenantId']}) "
                      f"- add to XERO_ORG_MAP to include it")
                continue
            print(f"Org: {tenant.get('tenantName')}  ->  Tenant_ID {org['tenant_id']}")
            extract_org(access, tenant, org["tenant_id"], org["default_site_id"])
            processed += 1
            print()
    print(f"Done. Extracted {processed} org(s) to {DATA_DIR}. Next: python API/xero_land.py")


if __name__ == "__main__":
    main()
