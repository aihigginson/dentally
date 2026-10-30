"""Export every Input.* table out of the AppDB to files, with a checksum manifest.

==> THIS IS THE ONE THAT SURVIVES ANYTHING. <== The in-database snapshot
(AppDB.Backup_Input_Snapshot.sql) is faster to roll back from, but it lives inside the blast radius:
a bad DROP, a wrong database, a restore over the top, and it is gone with the original. These files
are off-box.

WHY THE AppDB AND NOT THE WAREHOUSE. Everything in Input.* was typed by somebody and exists nowhere
else. Maple's targets are the owner's own, hand-set over months; the plan rates come from the
provider's spreadsheets; the hierarchy, the roles, the pay splits and the billing contact are all
decisions, not observations. The warehouse can be rebuilt from Dentally in an afternoon. This
cannot be rebuilt at all.

WHAT IT WRITES

    <out>/<db>_<UTC stamp>/
        manifest.json          row count + SHA-256 of every table, plus server, db and stamp
        Input.<table>.json     {"columns": [...], "rows": [[...], ...]}

  Values are JSON-safe: dates become ISO strings and decimals become strings, so a figure cannot be
  silently re-rounded through a float on the way back in. Restore_AppDB.py reverses it exactly.

USAGE

    python Backup_AppDB.py                       # AppDB-dev, into ./Backups
    python Backup_AppDB.py AppDB-prod            # prod
    python Backup_AppDB.py AppDB-prod D:\\safe    # prod, somewhere else

Authenticates with the owner's delegated token (az account get-access-token), the same way every
other AppDB script here does.
"""
import datetime
import decimal
import hashlib
import json
import os
import struct
import subprocess
import sys

import pyodbc

SERVER = 'sql-analytically.database.windows.net'
DB = sys.argv[1] if len(sys.argv) > 1 else 'AppDB-dev'
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'Backups')


def _conn():
    tok = subprocess.check_output(
        ['az', 'account', 'get-access-token', '--resource',
         'https://database.windows.net', '--query', 'accessToken', '-o', 'tsv'],
        shell=True).decode().strip().encode('utf-16-le')
    return pyodbc.connect(
        'Driver={ODBC Driver 18 for SQL Server};Server=%s,1433;Database=%s;'
        'Encrypt=yes;TrustServerCertificate=no;Login Timeout=30;' % (SERVER, DB),
        attrs_before={1256: struct.pack('<I%ds' % len(tok), len(tok), tok)})


def _jsonable(v):
    """Lossless for the types Input.* actually holds.

    A DECIMAL becomes a STRING, not a float: Target_Value is DECIMAL and a round trip through a
    double can move the last place. A target that comes back 0.0000001 different is a target
    somebody has to notice, so it must not be possible.
    """
    if v is None:
        return None
    if isinstance(v, decimal.Decimal):
        return str(v)
    if isinstance(v, (datetime.datetime, datetime.date, datetime.time)):
        return v.isoformat()
    if isinstance(v, (bytes, bytearray)):
        return v.hex()
    return v


def main():
    cn = _conn()
    cur = cn.cursor()

    # Every base table in Input, read from the catalogue rather than a hand-kept list -- a table
    # added to the schema and forgotten here is exactly the row nobody can get back.
    cur.execute("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES "
                "WHERE TABLE_SCHEMA = 'Input' AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME")
    tables = [r[0] for r in cur.fetchall()]

    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d_%H%M%SZ')
    folder = os.path.abspath(os.path.join(OUT, '%s_%s' % (DB, stamp)))
    os.makedirs(folder, exist_ok=True)

    print('%s / %s  ->  %s' % (SERVER.split('.')[0], DB, folder))
    manifest = {'server': SERVER, 'database': DB, 'taken_utc': stamp, 'tables': {}}

    for t in tables:
        # A computed column cannot be written back, so it is not exported: Node_Level and Node_Key
        # are derived from Level_Type/Level_Key/Tenant_ID and will recompute on insert.
        cur.execute("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS c "
                    "WHERE c.TABLE_SCHEMA = 'Input' AND c.TABLE_NAME = ? "
                    "  AND COLUMNPROPERTY(OBJECT_ID('Input.' + c.TABLE_NAME), c.COLUMN_NAME,"
                    "                     'IsComputed') = 0 "
                    "ORDER BY c.ORDINAL_POSITION", t)
        cols = [r[0] for r in cur.fetchall()]
        if not cols:
            print('  %-22s SKIPPED (no writable columns)' % t)
            continue

        cur.execute('SELECT %s FROM [Input].[%s]'
                    % (', '.join('[%s]' % c for c in cols), t))
        rows = [[_jsonable(v) for v in r] for r in cur.fetchall()]

        payload = json.dumps({'columns': cols, 'rows': rows},
                             indent=1, sort_keys=False, ensure_ascii=False)
        path = os.path.join(folder, 'Input.%s.json' % t)
        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(payload)

        digest = hashlib.sha256(payload.encode('utf-8')).hexdigest()
        manifest['tables'][t] = {'rows': len(rows), 'columns': len(cols), 'sha256': digest}
        print('  %-22s %6d row(s)  %s' % (t, len(rows), digest[:12]))

    with open(os.path.join(folder, 'manifest.json'), 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, indent=1)

    total = sum(v['rows'] for v in manifest['tables'].values())
    print('\n%d table(s), %d row(s) total' % (len(manifest['tables']), total))
    print('manifest: %s' % os.path.join(folder, 'manifest.json'))

    # ==> AN UNVERIFIED BACKUP IS NOT A BACKUP. <== Re-read what was just written and re-hash it,
    # so a half-written file or a full disk is found now rather than during a rollback.
    bad = []
    for t, meta in manifest['tables'].items():
        with open(os.path.join(folder, 'Input.%s.json' % t), encoding='utf-8') as fh:
            if hashlib.sha256(fh.read().encode('utf-8')).hexdigest() != meta['sha256']:
                bad.append(t)
    if bad:
        raise SystemExit('VERIFY FAILED -- re-read does not match: %s' % ', '.join(bad))
    print('verified: every file re-reads to its manifest hash')
    cn.close()


if __name__ == '__main__':
    main()
