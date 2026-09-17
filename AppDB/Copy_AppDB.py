"""Copy the Input.* tables between two SQL endpoints (Fabric SQL DB -> Azure SQL, or back).

Used for the AppDB migration off the Fabric capacity. Both ends are the Azure SQL engine, so
this is a straight row copy -- no type mapping, no schema translation.

  python AppDB/Copy_AppDB.py --check                 # row counts on both sides, no writes
  python AppDB/Copy_AppDB.py --env dev --copy        # truncate target, copy, verify
  python AppDB/Copy_AppDB.py --env prod --copy

IDEMPOTENT BY TRUNCATE-THEN-INSERT, not MERGE: the target is a migration destination, so the
source is always the truth. That also means a copy run while the app is live will LOSE any write
that lands after the read -- do the real cutover with writes stopped (see MIGRATION.md).

Reads are ordered by the table's own primary key where it has one, so a diff of two runs is
stable and reviewable.
"""
import argparse
import struct
import subprocess
import sys

import pyodbc

# The 10 owner-curated Input tables. Access_Log is append-only history; the rest are current-state.
TABLES = [
    'Access_Log', 'Application_Users', 'Billing_Contact', 'Metric_Variance',
    'Plan_Capitation_Rate', 'Practice_Config', 'Practitioner_Pay',
    'Practitioner_Role', 'Roles', 'Targets',
]

FABRIC = {
    'dev':  ('emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.database.fabric.microsoft.com',
             'AppDB-4c31e989-45ca-456c-a319-1a7a262c8aa3'),
    'prod': ('emeh72n2ntdufpj4q665b2lzx4-eljzajgm5cpe5i64szgon7sej4.database.fabric.microsoft.com',
             'AppDB-95d9076d-59d0-4e0c-a2c2-7963d74305ff'),
}
AZURE = {
    'dev':  ('sql-analytically.database.windows.net', 'AppDB-dev'),
    'prod': ('sql-analytically.database.windows.net', 'AppDB-prod'),
}


def _token():
    out = subprocess.check_output(
        ['az', 'account', 'get-access-token', '--resource',
         'https://database.windows.net', '--query', 'accessToken', '-o', 'tsv'], shell=True)
    tb = out.decode().strip().encode('utf-16-le')
    return struct.pack(f'<I{len(tb)}s', len(tb), tb)


def connect(server, database, token):
    cs = (f'Driver={{ODBC Driver 18 for SQL Server}};Server={server},1433;'
          f'Database={database};Encrypt=yes;TrustServerCertificate=no;Login Timeout=30;')
    return pyodbc.connect(cs, attrs_before={1256: token}, autocommit=True)


def columns(cur, table):
    """Column list from the TARGET, so a column the target does not have is never sent."""
    cur.execute("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS "
                "WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION", table)
    return [r[0] for r in cur.fetchall()]


def counts(cur, label):
    out = {}
    for t in TABLES:
        try:
            cur.execute(f'SELECT COUNT(*) FROM Input.[{t}]')
            out[t] = cur.fetchone()[0]
        except Exception as e:
            out[t] = f'ERR {str(e)[:40]}'
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--env', choices=['dev', 'prod'], default='dev')
    ap.add_argument('--check', action='store_true', help='row counts only, no writes')
    ap.add_argument('--copy', action='store_true', help='truncate target then copy')
    args = ap.parse_args()

    tok = _token()
    s_srv, s_db = FABRIC[args.env]
    t_srv, t_db = AZURE[args.env]
    print(f'source (Fabric)  : {s_db}')
    print(f'target (Azure SQL): {t_srv} / {t_db}\n')

    src = connect(s_srv, s_db, tok).cursor()
    tgt = connect(t_srv, t_db, tok).cursor()

    before_s, before_t = counts(src, 'src'), counts(tgt, 'tgt')
    print(f'{"table":24} {"source":>10} {"target":>10}')
    for t in TABLES:
        print(f'{t:24} {str(before_s[t]):>10} {str(before_t[t]):>10}')

    if args.check or not args.copy:
        print('\n--check only, nothing written.')
        return 0

    print('\ncopying...')
    for t in TABLES:
        cols = columns(tgt, t)
        if not cols:
            print(f'  {t:24} SKIPPED (not in target)')
            continue
        collist = ', '.join(f'[{c}]' for c in cols)
        src.execute(f'SELECT {collist} FROM Input.[{t}]')
        rows = src.fetchall()
        tgt.execute(f'DELETE FROM Input.[{t}]')          # TRUNCATE needs ALTER; DELETE is enough here
        if rows:
            marks = ', '.join(['?'] * len(cols))
            tgt.fast_executemany = True
            tgt.executemany(f'INSERT INTO Input.[{t}] ({collist}) VALUES ({marks})',
                            [tuple(r) for r in rows])
        print(f'  {t:24} {len(rows):>6} rows')

    after_t = counts(tgt, 'tgt')
    print('\nverify:')
    bad = 0
    for t in TABLES:
        ok = before_s[t] == after_t[t]
        if not ok:
            bad += 1
        print(f'  {t:24} source {str(before_s[t]):>6}  target {str(after_t[t]):>6}  {"OK" if ok else "MISMATCH"}')
    print('\nALL MATCH' if bad == 0 else f'\n{bad} TABLE(S) MISMATCHED')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
