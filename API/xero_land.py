"""
xero_land.py  --  Land the Xero profitability-slice data into OneLake as Delta stage
tables, the Bronze source for the Fabric build. Flattens the nested Xero entities
into flat rows and writes:

    stage_xero_accounts  -- chart of accounts (all classes)
    stage_xero_lines     -- one row per P&L transaction line (invoices, credit notes,
                            bank transactions, manual journals), RAW: no filtering,
                            no signing -- Silver applies window/status/direction/ex-tax.

Mirrors API/seed_onelake.py's OneLake write (delta-rs + InteractiveBrowserCredential).
Run after xero_extract.py.

Usage:  python API/xero_land.py
Requires: deltalake, pyarrow, pandas, azure-identity (already installed).
"""
import json
import os
import re
from datetime import datetime, timezone

import pandas as pd
import pyarrow as pa
from deltalake import write_deltalake
from azure.identity import InteractiveBrowserCredential

HERE     = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, "xero_data")

# OneLake — same LH_Dentally lakehouse as seed_onelake.py
WORKSPACE_GUID = "22e235e2-7a32-4451-b573-8d5eb8532a23"
LAKEHOUSE_GUID = "e6cc2011-bd96-4164-8f21-ceb340e25449"
ONELAKE_HOST   = "onelake.dfs.fabric.microsoft.com"

# Placeholder tenant for the Demo Company (NOT a real Dentally tenant) -- the slice
# proves the plumbing; real orgs map to real sites in the multi-tenant phase.
DEMO_TENANT_ID = 99

_cred = InteractiveBrowserCredential()


def storage_options():
    tok = _cred.get_token("https://storage.azure.com/.default")
    return {"bearer_token": tok.token}


def table_path(name):
    return (f"abfss://{WORKSPACE_GUID}@{ONELAKE_HOST}"
            f"/{LAKEHOUSE_GUID}/Tables/dbo/stage_{name}")


def load(name):
    with open(os.path.join(DATA_DIR, name + ".json")) as f:
        return json.load(f)


def parse_date(v):
    """Normalise Xero dates (ISO 'DateString' or '/Date(ms+offset)/') to YYYY-MM-DD."""
    if not v:
        return None
    m = re.search(r"/Date\((\d+)", str(v))
    if m:
        return datetime.fromtimestamp(int(m.group(1)) / 1000, tz=timezone.utc).date().isoformat()
    return str(v)[:10]


def write_stage(records, name):
    """Full overwrite as string-typed Delta (Bronze convention: raw strings)."""
    if not records:
        print(f"  {name}: 0 rows (skipped)")
        return

    def s(v):
        if v is None:
            return None
        if isinstance(v, (dict, list)):
            return json.dumps(v)
        return str(v)

    df  = pd.DataFrame([{k: s(v) for k, v in r.items()} for r in records]).astype("string")
    tbl = pa.Table.from_pandas(df, preserve_index=False)
    print(f"  {name}: writing {len(records):,} rows...", end="", flush=True)
    write_deltalake(table_path(name), tbl, mode="overwrite", schema_mode="overwrite",
                    storage_options=storage_options())
    print(" done.")


def flatten_lineitems(items, source, id_key, num_key, tenant, xtid):
    rows = []
    for it in items:
        base = {
            "Tenant_ID": tenant, "Xero_Tenant_ID": xtid, "Source": source,
            "Doc_ID": it.get(id_key), "Doc_Number": it.get(num_key),
            "Doc_Type": it.get("Type"), "Doc_Status": it.get("Status"),
            "Doc_Date": parse_date(it.get("DateString") or it.get("Date")),
            "Contact_Name": (it.get("Contact") or {}).get("Name"),
            "Line_Amount_Types": it.get("LineAmountTypes"),
        }
        for ln in it.get("LineItems", []):
            rows.append({**base,
                "Line_Item_ID": ln.get("LineItemID"),
                "Account_Code": ln.get("AccountCode"),
                "Account_ID":   ln.get("AccountID"),
                "Description":  ln.get("Description"),
                "Line_Amount":  ln.get("LineAmount"),
                "Tax_Amount":   ln.get("TaxAmount"),
                "Tracking":     ln.get("Tracking"),
            })
    return rows


def flatten_manual_journals(items, tenant, xtid):
    rows = []
    for mj in items:
        base = {
            "Tenant_ID": tenant, "Xero_Tenant_ID": xtid, "Source": "MANUALJOURNAL",
            "Doc_ID": mj.get("ManualJournalID"), "Doc_Number": None,
            "Doc_Type": "MANJRNL", "Doc_Status": mj.get("Status"),
            "Doc_Date": parse_date(mj.get("Date")),
            "Contact_Name": None, "Line_Amount_Types": mj.get("LineAmountTypes"),
        }
        for jl in mj.get("JournalLines", []):
            rows.append({**base,
                "Line_Item_ID": None,
                "Account_Code": jl.get("AccountCode"),
                "Account_ID":   jl.get("AccountID"),
                "Description":  jl.get("Description"),
                "Line_Amount":  jl.get("LineAmount"),
                "Tax_Amount":   None,
                "Tracking":     jl.get("Tracking"),
            })
    return rows


def main():
    saved = json.load(open(os.path.join(HERE, "xero_token.local.json")))
    demo  = next((t for t in saved["tenants"]
                  if "demo company" in (t.get("tenantName", "") or "").lower()),
                 saved["tenants"][0])
    tenant, xtid = DEMO_TENANT_ID, demo["tenantId"]
    print(f"Landing '{demo['tenantName']}' as Tenant_ID={tenant}\n")

    accounts = [{
        "Tenant_ID": tenant, "Xero_Tenant_ID": xtid,
        "Account_ID": a.get("AccountID"), "Code": a.get("Code"), "Name": a.get("Name"),
        "Type": a.get("Type"), "Class": a.get("Class"),
        "Reporting_Code": a.get("ReportingCode"), "Reporting_Code_Name": a.get("ReportingCodeName"),
        "Status": a.get("Status"),
    } for a in load("accounts")]

    lines  = flatten_lineitems(load("invoices_page1"),         "INVOICE",    "InvoiceID",         "InvoiceNumber",    tenant, xtid)
    lines += flatten_lineitems(load("creditnotes_page1"),      "CREDITNOTE", "CreditNoteID",      "CreditNoteNumber", tenant, xtid)
    lines += flatten_lineitems(load("banktransactions_page1"), "BANK",       "BankTransactionID", "Reference",        tenant, xtid)
    lines += flatten_manual_journals(load("manualjournals_page1"), tenant, xtid)

    write_stage(accounts, "xero_accounts")
    write_stage(lines,    "xero_lines")
    print("\nDone. Bronze can now read Stage views over stage_xero_accounts / stage_xero_lines.")


if __name__ == "__main__":
    main()
