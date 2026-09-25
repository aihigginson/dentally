"""
seed_onelake.py  --  Generate test tenant data locally and write directly to
                     OneLake Lakehouse Delta tables via delta-rs (no Spark needed).

Usage:
    python API/seed_onelake.py
    python API/seed_onelake.py --tenants 11        # single tenant
    python API/seed_onelake.py --tenants 11,12      # subset

Requirements (already installed):
    deltalake, pyarrow, pandas, azure-identity
"""
import sys, json, os, argparse, random
from collections import defaultdict
from datetime import datetime, timezone
import pandas as pd
import pyarrow as pa
from deltalake import write_deltalake
from azure.identity import InteractiveBrowserCredential

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_data import generate_tenant, _u5, _pp, _sundry, _wl, _acq, _cr, _contract

# ── OneLake config ────────────────────────────────────────────────────────────
# Workspace GUID: visible in Fabric URL (e.g. /groups/{GUID}/)
# Lakehouse GUID: open LH_Dentally in Fabric → copy from URL (/lakehouses/{GUID}/)
WORKSPACE_GUID = "22e235e2-7a32-4451-b573-8d5eb8532a23"   # default (dev); overridden by --env
LAKEHOUSE_GUID = "e6cc2011-bd96-4164-8f21-ceb340e25449"
ONELAKE_HOST   = "onelake.dfs.fabric.microsoft.com"

# Target OneLake by environment (--env). One script for both -- no divergent prod copy.
ENV_GUIDS = {
    "dev":  ("22e235e2-7a32-4451-b573-8d5eb8532a23", "e6cc2011-bd96-4164-8f21-ceb340e25449"),
    "prod": ("2490d322-e8cc-4e9e-a3dc-964ce6fe444f", "868da63e-6570-461c-aa46-eade0ce99f91"),
}

def table_path(table_name: str) -> str:
    return (
        f"abfss://{WORKSPACE_GUID}@{ONELAKE_HOST}"
        f"/{LAKEHOUSE_GUID}/Tables/dbo/stage_{table_name}"
    )

# ── Auth ──────────────────────────────────────────────────────────────────────
_cred = None

def get_storage_options() -> dict:
    global _cred
    token = _cred.get_token("https://storage.azure.com/.default")
    return {"bearer_token": token.token}

# ── Write helper (mirrors notebook write_stage) ───────────────────────────────
def write_stage(records: list, table_name: str):
    """Full overwrite of the entire table — all tenants in one write."""
    if not records:
        print(f"  {table_name}: 0 records (skipped)")
        return

    def _to_str(v):
        if v is None:                   return None
        if isinstance(v, bool):         return '1' if v else '0'
        if isinstance(v, (dict, list)): return json.dumps(v)
        return str(v)

    rows = [{k: _to_str(v) for k, v in r.items()} for r in records]
    df   = pd.DataFrame(rows).astype("string")
    tbl  = pa.Table.from_pandas(df, preserve_index=False)

    print(f"  {table_name}: writing {len(records):,} rows...", end="", flush=True)
    write_deltalake(
        table_path(table_name),
        tbl,
        mode            = "overwrite",
        # V011 data minimisation: "overwrite" (not "merge") so dropped columns are
        # removed from the Delta schema, not retained as nulls. The combined frame
        # already unions all tenants' columns, so this enforces the current schema.
        schema_mode     = "overwrite",
        storage_options = get_storage_options(),
    )
    print(" done.")


# ── Xero finance (synthetic P&L for margin demos) ─────────────────────────────
# Generates a Xero-shaped chart of accounts + monthly P&L transaction lines for a
# tenant, scaled to its ACTUAL Dentally invoiced revenue, and written to the same
# stage_xero_accounts / stage_xero_lines tables the Xero slice reads. Income tracks
# the practice's real monthly revenue; costs are a realistic labour-heavy dental
# structure giving ~15-20% net margin, so Gold.Fact_Finance yields a coherent,
# self-contained margin report. (Line_Amount_Types='NoTax' so Net_Amount = Line_Amount.)
# Tenant definitions and their synthetic Xero finance now live in seed_tenants, so the Bronze
# seeder can use them without pulling in pandas/pyarrow/deltalake.
from seed_tenants import generate_xero_finance, T11, T12, SEED_TENANTS



# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tenants', default='11,12',
                        help='Comma-separated tenant IDs to seed (default: 11,12)')
    parser.add_argument('--env', choices=['dev', 'prod'], default='dev',
                        help='Target OneLake environment (default: dev)')
    args = parser.parse_args()
    tenant_ids = [int(t.strip()) for t in args.tenants.split(',')]

    global WORKSPACE_GUID, LAKEHOUSE_GUID
    WORKSPACE_GUID, LAKEHOUSE_GUID = ENV_GUIDS[args.env]
    print(f"Target OneLake: {args.env}  (lakehouse {LAKEHOUSE_GUID})")

    if LAKEHOUSE_GUID == "REPLACE_WITH_LAKEHOUSE_GUID":
        print("ERROR: Set LAKEHOUSE_GUID at the top of this script before running.")
        print("       Open LH_Dentally in Fabric and copy the GUID from the URL.")
        sys.exit(1)

    print("Authenticating with Azure AD (browser window will open)...")
    global _cred
    _cred = InteractiveBrowserCredential()
    # Force auth prompt now rather than on first write
    _cred.get_token("https://storage.azure.com/.default")
    print("Authenticated.\n")

    load_ts = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S')
    print(f"Load timestamp : {load_ts}")
    print(f"Tenants to seed: {tenant_ids}\n")

    # Map from generate_tenant output key -> Stage table name
    TABLE_MAP = [
        # reference data
        ('practice',                   'practice',                   True),   # True = wrap in list
        ('sites',                      'sites',                      False),
        ('users',                      'users',                      False),
        ('practitioners',              'practitioners',              False),
        ('payment_plans',              'payment_plans',              False),
        ('treatments',                 'treatments',                 False),
        ('treatment_categories',       'treatment_categories',       False),
        ('acquisition_sources',        'acquisition_sources',        False),
        ('cancellation_reasons',       'cancellation_reasons',       False),
        ('waiting_lists',              'waiting_lists',              False),
        ('sundries',                   'sundries',                   False),
        ('contracts',                  'contracts',                  False),
        ('fees',                       'fees',                       False),
        ('diary_breaks',               'practitioner_diary_breaks',  False),
        ('rooms',                      'rooms',                      False),
        # transactional data
        ('patients',                   'patients',                   False),
        ('diary_entries',              'practitioner_diary_entries', False),
        ('appointments',               'appointments',               False),
        ('invoices',                   'invoices',                   False),
        ('invoice_items',              'invoice_items',              False),
        ('payments',                   'payments',                   False),
        ('treatment_plans',            'treatment_plans',            False),
        ('treatment_plan_items',       'treatment_plan_items',       False),
        ('recalls',                    'recalls',                    False),
        ('nhs_claims',                 'nhs_claims',                 False),
        ('patient_stats',              'patient_stats',              False),
        ('payment_allocations',        'payment_allocations',        False),
        ('payment_explanations',       'payment_explanations',       False),
        ('treatment_appts',            'treatment_appointments',     False),
        ('patient_referrals',          'patient_referrals',         False),
    ]

    # ── Phase 1: generate all tenant data and tag with tenant_id ─────────────
    combined = {stage_name: [] for _, stage_name, _ in TABLE_MAP}
    xero_accounts_all, xero_lines_all = [], []
    xero_orgs_all, xero_tracking_all  = [], []

    for tid in tenant_ids:
        tdef = SEED_TENANTS[tid]
        print(f'Generating Tenant {tid}: {tdef["practice"]["name"]}  '
              f'({tdef["n_patients"]:,} patients)...', flush=True)
        data = generate_tenant(tdef)
        print(f"  patients={len(data['patients']):,}  "
              f"apts={len(data['appointments']):,}  "
              f"plans={len(data['treatment_plans']):,}  "
              f"invoices={len(data['invoices']):,}  "
              f"claims={len(data['nhs_claims']):,}")

        xa, xl, xo, xt = generate_xero_finance(tdef, data, load_ts)
        xero_accounts_all.extend(xa); xero_lines_all.extend(xl)
        xero_orgs_all.append(xo); xero_tracking_all.extend(xt)
        print(f"  xero: {len(xa)} accounts, {len(xl):,} P&L lines")

        for data_key, stage_name, wrap in TABLE_MAP:
            records = [data[data_key]] if wrap else data[data_key]
            for r in records:
                r['tenant_id']          = str(tid)
                r['DW_Stage_Loaded_At'] = load_ts
            combined[stage_name].extend(records)

    # ── Phase 2: write each table as a single full overwrite ─────────────────
    print('\nWriting to OneLake (full overwrite per table)...')
    for _, stage_name, _ in TABLE_MAP:
        write_stage(combined[stage_name], stage_name)

    # Xero finance stage tables (PascalCase schema the Xero slice reads)
    write_stage(xero_accounts_all, 'xero_accounts')
    write_stage(xero_lines_all,    'xero_lines')
    write_stage(xero_orgs_all,     'xero_orgs')
    write_stage(xero_tracking_all, 'xero_tracking')

    print('\nAll tenants seeded. Run Orchestrate_Build (build-only) for tenants 11-14.')


if __name__ == '__main__':
    main()
