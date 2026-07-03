"""
xero_extract.py  --  Profitability-slice extract for the connected Xero org
(targets the Demo Company). Refreshes the access token (persisting the rotated
refresh token), then pulls the chart of accounts, the Profit & Loss report, and
samples of invoices / bank transactions / manual journals / payments. Raw JSON is
saved to API/xero_data/ (gitignored) and a summary is printed.

Usage:  python API/xero_extract.py
"""
import base64
import importlib.util
import json
import os
from collections import Counter
from datetime import date, timedelta

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "xero_creds_local", os.path.join(HERE, "xero_creds.local.py"))
creds = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(creds)

TOKEN_FILE = os.path.join(HERE, "xero_token.local.json")
DATA_DIR   = os.path.join(HERE, "xero_data")
TOKEN_URL  = "https://identity.xero.com/connect/token"
API_BASE   = "https://api.xero.com/api.xro/2.0"


def _basic():
    raw = f"{creds.XERO_CLIENT_ID}:{creds.XERO_CLIENT_SECRET}".encode()
    return "Basic " + base64.b64encode(raw).decode()


def load_saved():
    with open(TOKEN_FILE) as f:
        return json.load(f)


def save_saved(saved):
    with open(TOKEN_FILE, "w") as f:
        json.dump(saved, f, indent=2)


def refresh(saved):
    """Swap the refresh token for a fresh access token; persist the rotated
    refresh token (Xero rotates it on every use)."""
    r = requests.post(TOKEN_URL, headers={
        "Authorization": _basic(),
        "Content-Type":  "application/x-www-form-urlencoded",
    }, data={
        "grant_type":    "refresh_token",
        "refresh_token": saved["tokens"]["refresh_token"],
    })
    r.raise_for_status()
    saved["tokens"].update(r.json())
    save_saved(saved)
    return saved["tokens"]["access_token"]


def pick_tenant(saved):
    for t in saved["tenants"]:
        if "demo company" in (t.get("tenantName", "") or "").lower():
            return t
    return saved["tenants"][0]


def xget(path, access, tenant_id, params=None):
    r = requests.get(API_BASE + path, headers={
        "Authorization":  "Bearer " + access,
        "Xero-tenant-id": tenant_id,
        "Accept":         "application/json",
    }, params=params or {})
    r.raise_for_status()
    return r.json()


def save_json(name, obj):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(os.path.join(DATA_DIR, name + ".json"), "w") as f:
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
                    val   = cells[-1].get("Value", "") if len(cells) > 1 else ""
                    mark  = "=" if rt == "SummaryRow" else " "
                    if label or val:
                        print("   " * indent + f"{mark} {label}: {val}")
    walk(report.get("Rows", []))


def main():
    saved  = load_saved()
    tenant = pick_tenant(saved)
    tid    = tenant["tenantId"]
    print(f"Org: {tenant['tenantName']}  ({tid})")
    access = refresh(saved)
    print("Token refreshed.\n")

    # 1. Chart of accounts
    accounts = xget("/Accounts", access, tid)["Accounts"]
    save_json("accounts", accounts)
    print(f"Accounts: {len(accounts)}")
    for cls, n in Counter(a.get("Class", "?") for a in accounts).most_common():
        print(f"   {cls}: {n}")
    print()

    # 2. Profit & Loss — last 12 months
    to_d, from_d = date.today(), date.today() - timedelta(days=365)
    pl = xget("/Reports/ProfitAndLoss", access, tid,
              {"fromDate": from_d.isoformat(), "toDate": to_d.isoformat()})
    save_json("profit_and_loss", pl)
    print(f"Profit & Loss ({from_d} to {to_d}):")
    print_pl(pl["Reports"][0])
    print()

    # 3. Transaction samples (page 1 each)
    for path, key in [("/Invoices", "Invoices"),
                      ("/CreditNotes", "CreditNotes"),
                      ("/BankTransactions", "BankTransactions"),
                      ("/ManualJournals", "ManualJournals"),
                      ("/Payments", "Payments")]:
        try:
            rows = xget(path, access, tid, {"page": 1}).get(key, [])
        except requests.HTTPError as e:
            print(f"{key}: HTTP {e.response.status_code} (scope?) - skipped")
            continue
        save_json(key.lower() + "_page1", rows)
        more = "  (>=100 - more pages exist)" if len(rows) >= 100 else ""
        print(f"{key}: {len(rows)} on page 1{more}")

    print(f"\nRaw JSON saved to {DATA_DIR}")


if __name__ == "__main__":
    main()
