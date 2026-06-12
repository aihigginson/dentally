"""
Load_Mapping_From_Template.py
Reads a completed mapping template and loads it into the Input schema.
Existing rows for the tenant+entity are replaced on each run.

Entities:  treatment_category | acquisition_source | cancellation_reason | payment_plan

Usage:
    py Scripts/Load_Mapping_From_Template.py ^
        --server <fabric-sql-endpoint> ^
        --database WH_Dentally ^
        --input Mappings/T11_treatment_category.xlsx ^
        [--auth interactive]

Tenant and entity are derived from the filename (T{id}_{entity}.xlsx).
Rows where the Standard column is blank are skipped.
"""

import argparse
import re
import struct
import sys
from pathlib import Path

import pyodbc
import openpyxl

# ── Entity configuration (mirrors Generate_Mapping_Template.py) ───────────────

ENTITY_CONFIG = {
    'treatment_category': {
        'input_table':  'Input.Treatment_Category_Map',
        'source_col':   'Source_Treatment_Category',
        'standard_col': 'Standard_Treatment_Category',
    },
    'acquisition_source': {
        'input_table':  'Input.Acquisition_Source_Map',
        'source_col':   'Source_Acquisition_Source',
        'standard_col': 'Standard_Acquisition_Source',
    },
    'cancellation_reason': {
        'input_table':  'Input.Cancellation_Reason_Map',
        'source_col':   'Source_Cancellation_Reason',
        'standard_col': 'Standard_Cancellation_Reason',
    },
    'payment_plan': {
        'input_table':  'Input.Payment_Plan_Map',
        'source_col':   'Source_Payment_Plan',
        'standard_col': 'Standard_Payment_Plan',
    },
}

# ── Auth ──────────────────────────────────────────────────────────────────────

def _token_bytes(token_str):
    b = token_str.encode('utf-16-le')
    return struct.pack(f'<I{len(b)}s', len(b), b)


def connect(server, database, username=None, auth='default'):
    from azure.identity import DefaultAzureCredential, InteractiveBrowserCredential
    cred = (InteractiveBrowserCredential(login_hint=username)
            if auth == 'interactive' else DefaultAzureCredential())
    token = cred.get_token('https://database.windows.net/.default')
    conn = pyodbc.connect(
        'Driver={ODBC Driver 18 for SQL Server};'
        f'Server={server},1433;'
        f'Database={database};'
        'Encrypt=yes;',
        attrs_before={1256: _token_bytes(token.token)},
    )
    conn.autocommit = True
    return conn

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--server',   required=True)
    p.add_argument('--database', required=True)
    p.add_argument('--input',    required=True, help='Path to completed template, e.g. Mappings/T11_treatment_category.xlsx')
    p.add_argument('--username', default=None)
    p.add_argument('--auth',     default='default', choices=['default', 'interactive'])
    args = p.parse_args()

    # ── Parse tenant and entity from filename ─────────────────────────────────
    stem = Path(args.input).stem   # e.g. T11_treatment_category
    m = re.match(r'^T(\d+)_(.+)$', stem)
    if not m:
        print('Filename must be T{tenant_id}_{entity}.xlsx', file=sys.stderr)
        sys.exit(1)
    tenant_id = int(m.group(1))
    entity    = m.group(2)

    if entity not in ENTITY_CONFIG:
        print(f'Unknown entity "{entity}". Choices: {list(ENTITY_CONFIG)}', file=sys.stderr)
        sys.exit(1)

    cfg = ENTITY_CONFIG[entity]

    # ── Read workbook ─────────────────────────────────────────────────────────
    wb = openpyxl.load_workbook(args.input, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(min_row=2, values_only=True))

    mappings = []
    skipped  = 0
    for row in rows:
        source   = str(row[0]).strip() if row[0] is not None else ''
        standard = str(row[1]).strip() if row[1] is not None else ''
        if not source or not standard:
            skipped += 1
            continue
        mappings.append((tenant_id, source, standard))

    if not mappings:
        print('No complete rows to load (all rows blank or missing Standard value).')
        sys.exit(0)

    print(f'Tenant {tenant_id} / {entity}: {len(mappings)} rows to load, {skipped} skipped.')

    # ── Write to warehouse ────────────────────────────────────────────────────
    print(f'Connecting to {args.server} / {args.database} ...')
    try:
        conn = connect(args.server, args.database, args.username, args.auth)
    except Exception as e:
        print(f'Connection failed: {e}', file=sys.stderr)
        sys.exit(1)

    cur = conn.cursor()

    table        = cfg['input_table']
    source_col   = cfg['source_col']
    standard_col = cfg['standard_col']

    # Delete existing rows for this tenant
    cur.execute(f'DELETE FROM {table} WHERE Tenant_ID = ?', [tenant_id])
    print(f'Deleted existing rows for tenant {tenant_id}.')

    # Insert new rows
    cur.fast_executemany = True
    cur.executemany(
        f'INSERT INTO {table} '
        f'(Tenant_ID, [{source_col}], [{standard_col}], DW_Created_At, DW_Updated_At) '
        f'VALUES (?, ?, ?, GETUTCDATE(), GETUTCDATE())',
        [(tid, src, std) for tid, src, std in mappings],
    )
    print(f'Inserted {len(mappings)} rows into {table}.')

    conn.close()
    print('Done.')


if __name__ == '__main__':
    main()
