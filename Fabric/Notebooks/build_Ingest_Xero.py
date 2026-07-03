"""
build_Ingest_Xero.py  --  Generator for Ingest_Xero.ipynb (Fabric notebook).

Edit THIS file, then run `python build_Ingest_Xero.py` to regenerate the notebook.
We never hand-edit the .ipynb JSON: source must be a list-of-lines and manual edits
have corrupted these notebooks before. Cell sources are plain Python strings here and
this script emits valid nbformat-4 JSON (source split to lines).
"""
import json
import os

# Each cell: (raw source string, is_parameters_cell). Keep cell code free of triple
# quotes. Runs in Fabric: `spark` and `notebookutils` are provided by the runtime.
CELLS = [
    # 0 -- parameters (Fabric overrides at pipeline runtime) -------------------
    (r'''# Parameters -- Fabric overrides these at pipeline runtime.
keyvault_url = "https://kv-analytically.vault.azure.net/"
xero_env     = "dev"   # which env's tokens to read: xero-tokens-<env> (dev|prod). PROD passes "prod".
only_org     = ""      # optional Xero tenantId to restrict to; blank = every mapped org
''', True),

    # 1 -- imports -------------------------------------------------------------
    (r'''import json
import time
import base64
import re
from datetime import date, datetime, timezone

import requests
from pyspark.sql.types import StringType, StructType, StructField
import notebookutils
''', False),

    # 2 -- Key Vault I/O -------------------------------------------------------
    (r'''# --- Key Vault I/O -----------------------------------------------------------
# Secrets used (tokens + org map are per-env: dev(Demo) and prod(clients) are isolated):
#   xero-client-id, xero-client-secret : the Xero app credentials (shared)
#   xero-org-map-<env> : JSON {"<xeroTenantId>": {"tenant_id": N, "default_site_id": "S"}}
#   xero-tokens-<env>  : JSON {"<connKey>": {"tokens": {...}, "tenants": [...]}} -- one
#                        entry per OAuth consent; refresh tokens rotate and are written back.
# The run identity (pipeline/workspace) needs secrets get + set on the vault.

def kv_get(name):
    return notebookutils.credentials.getSecret(keyvault_url, name)

def kv_set(name, value):
    # notebookutils has no setSecret; write via the Key Vault REST data plane with an
    # AAD token for the vault. If "keyvault" errors as an audience, try "vault" or
    # "https://vault.azure.net". Requires secret 'set' permission for the run identity.
    token = notebookutils.credentials.getToken("keyvault")
    resp = requests.put(
        keyvault_url.rstrip("/") + "/secrets/" + name + "?api-version=7.4",
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
        json={"value": value},
    )
    resp.raise_for_status()
''', False),

    # 3 -- config --------------------------------------------------------------
    (r'''XERO_CLIENT_ID     = kv_get("xero-client-id")
XERO_CLIENT_SECRET = kv_get("xero-client-secret")
ORG_MAP = json.loads(kv_get("xero-org-map-" + xero_env))
TOKENS  = json.loads(kv_get("xero-tokens-" + xero_env))   # env-isolated: dev(Demo) vs prod(clients)

TOKEN_URL = "https://identity.xero.com/connect/token"
API_BASE  = "https://api.xero.com/api.xro/2.0"
PAGE_SIZE = 100
MAX_429   = 6

def basic_auth():
    raw = (XERO_CLIENT_ID + ":" + XERO_CLIENT_SECRET).encode()
    return "Basic " + base64.b64encode(raw).decode()

def resolve_org(tenant):
    entry = ORG_MAP.get(tenant.get("tenantId"))
    if entry:
        return entry["tenant_id"], entry.get("default_site_id")
    if "demo company" in (tenant.get("tenantName", "") or "").lower():
        return 99, None
    return None, None
''', False),

    # 4 -- Xero API helpers ----------------------------------------------------
    (r'''def refresh(blob):
    r = requests.post(TOKEN_URL,
        headers={"Authorization": basic_auth(),
                 "Content-Type": "application/x-www-form-urlencoded"},
        data={"grant_type": "refresh_token",
              "refresh_token": blob["tokens"]["refresh_token"]})
    r.raise_for_status()
    blob["tokens"].update(r.json())
    return blob["tokens"]["access_token"]

def xget(path, access, tid, params=None):
    for _ in range(MAX_429):
        r = requests.get(API_BASE + path,
            headers={"Authorization": "Bearer " + access,
                     "Xero-tenant-id": tid, "Accept": "application/json"},
            params=params or {})
        if r.status_code == 429:
            wait = int(r.headers.get("Retry-After", 5)) + 1
            print("      429 rate-limited; sleeping", wait, "s")
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError("Rate-limited repeatedly on " + path)

def xget_all(path, key, access, tid):
    out, page = [], 1
    while True:
        rows = xget(path, access, tid, {"page": page}).get(key, []) or []
        out.extend(rows)
        if len(rows) < PAGE_SIZE:
            return out
        page += 1
''', False),

    # 5 -- flatten helpers (ported from API/xero_land.py) ----------------------
    (r'''def parse_date(v):
    if not v:
        return None
    m = re.search(r"/Date\((\d+)", str(v))
    if m:
        return datetime.fromtimestamp(int(m.group(1)) / 1000, tz=timezone.utc).date().isoformat()
    return str(v)[:10]

def tracking_pairs(tracking):
    pairs = [(t.get("Name"), t.get("Option")) for t in (tracking or [])]
    cols = {}
    for i in range(2):
        cat, opt = pairs[i] if i < len(pairs) else (None, None)
        cols["Tracking_Cat_" + str(i + 1)] = cat
        cols["Tracking_Opt_" + str(i + 1)] = opt
    return cols

def flatten_lineitems(items, source, id_key, num_key, tenant, xtid):
    rows = []
    for it in items:
        base = {"Tenant_ID": tenant, "Xero_Tenant_ID": xtid, "Source": source,
                "Doc_ID": it.get(id_key), "Doc_Number": it.get(num_key),
                "Doc_Type": it.get("Type"), "Doc_Status": it.get("Status"),
                "Doc_Date": parse_date(it.get("DateString") or it.get("Date")),
                "Contact_Name": (it.get("Contact") or {}).get("Name"),
                "Line_Amount_Types": it.get("LineAmountTypes")}
        for ln in it.get("LineItems", []):
            row = dict(base)
            row.update({"Line_Item_ID": ln.get("LineItemID"),
                        "Account_Code": ln.get("AccountCode"),
                        "Account_ID": ln.get("AccountID"),
                        "Description": ln.get("Description"),
                        "Line_Amount": ln.get("LineAmount"),
                        "Tax_Amount": ln.get("TaxAmount"),
                        "Tracking": ln.get("Tracking")})
            row.update(tracking_pairs(ln.get("Tracking")))
            rows.append(row)
    return rows

def flatten_manual_journals(items, tenant, xtid):
    rows = []
    for mj in items:
        base = {"Tenant_ID": tenant, "Xero_Tenant_ID": xtid, "Source": "MANUALJOURNAL",
                "Doc_ID": mj.get("ManualJournalID"), "Doc_Number": None,
                "Doc_Type": "MANJRNL", "Doc_Status": mj.get("Status"),
                "Doc_Date": parse_date(mj.get("Date")),
                "Contact_Name": None, "Line_Amount_Types": mj.get("LineAmountTypes")}
        for jl in mj.get("JournalLines", []):
            row = dict(base)
            row.update({"Line_Item_ID": None,
                        "Account_Code": jl.get("AccountCode"),
                        "Account_ID": jl.get("AccountID"),
                        "Description": jl.get("Description"),
                        "Line_Amount": jl.get("LineAmount"),
                        "Tax_Amount": None,
                        "Tracking": jl.get("Tracking")})
            row.update(tracking_pairs(jl.get("Tracking")))
            rows.append(row)
    return rows

def flatten_tracking(cats, tenant, xtid):
    rows = []
    for c in cats:
        for opt in c.get("Options", []):
            rows.append({"Tenant_ID": tenant, "Xero_Tenant_ID": xtid,
                         "Tracking_Category_ID": c.get("TrackingCategoryID"),
                         "Category_Name": c.get("Name"), "Category_Status": c.get("Status"),
                         "Tracking_Option_ID": opt.get("TrackingOptionID"),
                         "Option_Name": opt.get("Name"), "Option_Status": opt.get("Status")})
    return rows
''', False),

    # 6 -- write_stage (Spark Delta, per-tenant replaceWhere) ------------------
    (r'''def to_str(v):
    if v is None:
        return None
    if isinstance(v, (dict, list)):
        return json.dumps(v)
    return str(v)

def write_stage(records, table_name, tenant):
    full = "stage_" + table_name
    if not records:
        print("  " + table_name + ": 0 rows")
        return
    keys = set()
    for r in records:
        keys.update(r.keys())
    schema = StructType([StructField(k, StringType(), True) for k in sorted(keys)])
    str_records = [{k: to_str(r.get(k)) for k in keys} for r in records]
    df = spark.createDataFrame(str_records, schema=schema)
    if spark.catalog.tableExists(full):
        # Overwrite only this tenant's rows; other tenants are preserved. mergeSchema
        # lets new columns (e.g. Tracking_Cat_1) appear without failing.
        df.write.format("delta").mode("overwrite") \
            .option("replaceWhere", "Tenant_ID = '" + str(tenant) + "'") \
            .option("mergeSchema", "true").saveAsTable(full)
    else:
        df.write.format("delta").mode("overwrite") \
            .option("overwriteSchema", "true").saveAsTable(full)
    print("  " + table_name + ": " + str(len(records)) + " rows -> " + full)
''', False),

    # 7 -- main: refresh-first (persist), then extract + land ------------------
    (r'''# Phase 1: refresh every connection FIRST and persist the rotated refresh tokens,
# so a later extraction failure can't strand a rotated (now-invalid) token.
access_by_conn = {}
for conn_key, blob in TOKENS.items():
    access_by_conn[conn_key] = refresh(blob)
kv_set("xero-tokens-" + xero_env, json.dumps(TOKENS))
print("Refreshed", len(TOKENS), "connection(s); tokens persisted.")

# Phase 2: extract + land per mapped org.
processed = 0
for conn_key, blob in TOKENS.items():
    access = access_by_conn[conn_key]
    for tenant in blob.get("tenants", []):
        xtid = tenant["tenantId"]
        if only_org and xtid != only_org:
            continue
        tenant_id, default_site = resolve_org(tenant)
        if tenant_id is None:
            print("Skip unmapped org:", tenant.get("tenantName"), xtid)
            continue
        print("Org:", tenant.get("tenantName"), "-> Tenant_ID", tenant_id)

        write_stage([{"Tenant_ID": tenant_id, "Xero_Tenant_ID": xtid,
                      "Tenant_Name": tenant.get("tenantName"),
                      "Default_Site_ID": default_site}], "xero_orgs", tenant_id)

        accounts = xget("/Accounts", access, xtid)["Accounts"]
        acc_rows = [{"Tenant_ID": tenant_id, "Xero_Tenant_ID": xtid,
                     "Account_ID": a.get("AccountID"), "Code": a.get("Code"),
                     "Name": a.get("Name"), "Type": a.get("Type"), "Class": a.get("Class"),
                     "Reporting_Code": a.get("ReportingCode"),
                     "Reporting_Code_Name": a.get("ReportingCodeName"),
                     "Status": a.get("Status")} for a in accounts]
        write_stage(acc_rows, "xero_accounts", tenant_id)

        tracking = xget("/TrackingCategories", access, xtid).get("TrackingCategories", []) or []
        write_stage(flatten_tracking(tracking, tenant_id, xtid), "xero_tracking", tenant_id)

        lines = []
        lines += flatten_lineitems(xget_all("/Invoices", "Invoices", access, xtid),
                                   "INVOICE", "InvoiceID", "InvoiceNumber", tenant_id, xtid)
        lines += flatten_lineitems(xget_all("/CreditNotes", "CreditNotes", access, xtid),
                                   "CREDITNOTE", "CreditNoteID", "CreditNoteNumber", tenant_id, xtid)
        lines += flatten_lineitems(xget_all("/BankTransactions", "BankTransactions", access, xtid),
                                   "BANK", "BankTransactionID", "Reference", tenant_id, xtid)
        lines += flatten_manual_journals(xget_all("/ManualJournals", "ManualJournals", access, xtid),
                                         tenant_id, xtid)
        write_stage(lines, "xero_lines", tenant_id)
        processed += 1

print("Done. Extracted", processed, "org(s). Bronze/Silver/Gold Xero loads run next in the pipeline.")
''', False),
]


def build():
    cells = []
    for src, is_params in CELLS:
        cell = {
            "cell_type": "code",
            "execution_count": None,
            "metadata": {"tags": ["parameters"]} if is_params else {},
            "outputs": [],
            "source": src.splitlines(keepends=True),
        }
        cells.append(cell)
    nb = {
        "cells": cells,
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python"},
        },
        "nbformat": 4,
        "nbformat_minor": 4,
    }
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Ingest_Xero.ipynb")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(nb, f, indent=1)
        f.write("\n")
    return out


if __name__ == "__main__":
    path = build()
    print("Wrote", path)
