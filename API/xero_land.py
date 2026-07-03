"""
xero_land.py  --  Land the extracted Xero data into OneLake as Delta stage tables,
the Bronze source for the Fabric build.

Iterates every per-org folder written by xero_extract.py (API/xero_data/<org>/),
reads each _meta.json for the Dentally Tenant_ID + default site, flattens the nested
Xero entities into flat rows, and writes the full multi-org snapshot to:

    stage_xero_accounts  -- chart of accounts (all classes), per org
    stage_xero_lines     -- one row per P&L transaction line (invoices, credit notes,
                            bank transactions, manual journals), RAW: no filtering,
                            no signing -- Silver applies window/status/direction/ex-tax.
                            Each line keeps its Tracking JSON for site resolution.
    stage_xero_tracking  -- tracking categories + options per org (site-split source)
    stage_xero_orgs      -- one row per org: Tenant_ID, Xero org id/name, default site

Snapshot: each run OVERWRITES the stage with the full current picture across all orgs
(Bronze MERGEs from it). Mirrors API/seed_onelake.py's OneLake write.

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

_cred = InteractiveBrowserCredential()


def storage_options():
    tok = _cred.get_token("https://storage.azure.com/.default")
    return {"bearer_token": tok.token}


def table_path(name):
    return (f"abfss://{WORKSPACE_GUID}@{ONELAKE_HOST}"
            f"/{LAKEHOUSE_GUID}/Tables/dbo/stage_{name}")


def load(org_dir, name):
    path = os.path.join(DATA_DIR, org_dir, name + ".json")
    if not os.path.exists(path):
        return []
    with open(path) as f:
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


def _tracking_pairs(tracking):
    """Flatten a line's Tracking list into up to two (Category, Option) columns so the
    warehouse can map option->site with plain equality joins (Fabric has no OPENJSON).
    Practices split by site with a single location category; two covers the rare case."""
    pairs = [(t.get("Name"), t.get("Option")) for t in (tracking or [])]
    cols = {}
    for i in range(2):
        cat, opt = pairs[i] if i < len(pairs) else (None, None)
        cols[f"Tracking_Cat_{i+1}"] = cat
        cols[f"Tracking_Opt_{i+1}"] = opt
    return cols


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
                **_tracking_pairs(ln.get("Tracking")),
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
                **_tracking_pairs(jl.get("Tracking")),
            })
    return rows


def flatten_tracking(cats, tenant, xtid):
    rows = []
    for c in cats:
        for opt in c.get("Options", []):
            rows.append({
                "Tenant_ID": tenant, "Xero_Tenant_ID": xtid,
                "Tracking_Category_ID": c.get("TrackingCategoryID"),
                "Category_Name": c.get("Name"), "Category_Status": c.get("Status"),
                "Tracking_Option_ID": opt.get("TrackingOptionID"),
                "Option_Name": opt.get("Name"), "Option_Status": opt.get("Status"),
            })
    return rows


def org_dirs():
    """Every folder written by the extractor that has a _meta.json."""
    if not os.path.isdir(DATA_DIR):
        return []
    return [d for d in sorted(os.listdir(DATA_DIR))
            if os.path.exists(os.path.join(DATA_DIR, d, "_meta.json"))]


def main():
    dirs = org_dirs()
    if not dirs:
        raise SystemExit(f"No extracted orgs in {DATA_DIR}. Run python API/xero_extract.py first.")

    accounts, lines, tracking, orgs = [], [], [], []
    for d in dirs:
        meta = load(d, "_meta")
        tenant, xtid = meta["tenant_id"], meta["xero_tenant_id"]
        print(f"Org '{meta.get('tenant_name')}'  ->  Tenant_ID {tenant}")

        orgs.append({
            "Tenant_ID": tenant, "Xero_Tenant_ID": xtid,
            "Tenant_Name": meta.get("tenant_name"),
            "Default_Site_ID": meta.get("default_site_id"),
        })

        accounts += [{
            "Tenant_ID": tenant, "Xero_Tenant_ID": xtid,
            "Account_ID": a.get("AccountID"), "Code": a.get("Code"), "Name": a.get("Name"),
            "Type": a.get("Type"), "Class": a.get("Class"),
            "Reporting_Code": a.get("ReportingCode"), "Reporting_Code_Name": a.get("ReportingCodeName"),
            "Status": a.get("Status"),
        } for a in load(d, "accounts")]

        lines += flatten_lineitems(load(d, "invoices"),         "INVOICE",    "InvoiceID",         "InvoiceNumber",    tenant, xtid)
        lines += flatten_lineitems(load(d, "creditnotes"),      "CREDITNOTE", "CreditNoteID",      "CreditNoteNumber", tenant, xtid)
        lines += flatten_lineitems(load(d, "banktransactions"), "BANK",       "BankTransactionID", "Reference",        tenant, xtid)
        lines += flatten_manual_journals(load(d, "manualjournals"), tenant, xtid)

        tracking += flatten_tracking(load(d, "tracking_categories"), tenant, xtid)

    print()
    write_stage(orgs,     "xero_orgs")
    write_stage(accounts, "xero_accounts")
    write_stage(lines,    "xero_lines")
    write_stage(tracking, "xero_tracking")
    print("\nDone. Bronze can now read the Stage views over the stage_xero_* tables.")


if __name__ == "__main__":
    main()
