"""Put an Input.* table back from a Backup_AppDB.py export.

==> IT REFUSES BEFORE IT GUESSES. <== It verifies the manifest hash of every file it is about to
read, checks the target table still has the columns the export recorded, and will not run against a
database the export did not come from unless you say so explicitly. A restore that half-works is
worse than one that does not start.

Table by table, deliberately: the thing you usually need back is Targets, and rewriting nine other
tables to get it is risk you did not ask for.

    python Restore_AppDB.py <backup folder> --list
    python Restore_AppDB.py <backup folder> Targets --dry-run
    python Restore_AppDB.py <backup folder> Targets
    python Restore_AppDB.py <backup folder> ALL

A restore is DELETE-then-INSERT inside one transaction, so the table is either wholly the backup's
or wholly untouched. Decimals come back from their string form, so no figure moves in the last
place.
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


def _conn(db):
    tok = subprocess.check_output(
        ['az', 'account', 'get-access-token', '--resource',
         'https://database.windows.net', '--query', 'accessToken', '-o', 'tsv'],
        shell=True).decode().strip().encode('utf-16-le')
    return pyodbc.connect(
        'Driver={ODBC Driver 18 for SQL Server};Server=%s,1433;Database=%s;'
        'Encrypt=yes;TrustServerCertificate=no;Login Timeout=30;' % (SERVER, db),
        attrs_before={1256: struct.pack('<I%ds' % len(tok), len(tok), tok)},
        autocommit=False)                      # one transaction per table, see below


def _load(folder, table, meta):
    path = os.path.join(folder, 'Input.%s.json' % table)
    with open(path, encoding='utf-8') as fh:
        raw = fh.read()
    if hashlib.sha256(raw.encode('utf-8')).hexdigest() != meta['sha256']:
        raise SystemExit('REFUSING: %s does not match its manifest hash. The export is damaged.'
                         % path)
    return json.loads(raw)


def _typed(v, dtype):
    """Back to the type the column holds, from the JSON-safe form the export wrote."""
    if v is None:
        return None
    if dtype in ('decimal', 'numeric', 'money', 'smallmoney'):
        return decimal.Decimal(v)
    if dtype in ('datetime2', 'datetime', 'smalldatetime'):
        return datetime.datetime.fromisoformat(v)
    if dtype == 'date':
        return datetime.date.fromisoformat(v)
    if dtype == 'time':
        return datetime.time.fromisoformat(v)
    if dtype in ('varbinary', 'binary'):
        return bytes.fromhex(v)
    return v


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    folder = os.path.abspath(sys.argv[1])
    args = sys.argv[2:]
    dry = '--dry-run' in args
    args = [a for a in args if not a.startswith('--')]

    with open(os.path.join(folder, 'manifest.json'), encoding='utf-8') as fh:
        manifest = json.load(fh)
    db = manifest['database']
    print('backup : %s' % folder)
    print('taken  : %s from %s' % (manifest['taken_utc'], db))

    if not args or '--list' in sys.argv:
        for t, m in sorted(manifest['tables'].items()):
            print('  %-22s %6d row(s)' % (t, m['rows']))
        return

    wanted = sorted(manifest['tables']) if args[0].upper() == 'ALL' else args
    for t in wanted:
        if t not in manifest['tables']:
            raise SystemExit('REFUSING: %s is not in this backup.' % t)

    cn = _conn(db)
    cur = cn.cursor()

    for t in wanted:
        meta = manifest['tables'][t]
        data = _load(folder, t, meta)
        cols = data['columns']

        # The table must still look like the export, or the rows would land in the wrong columns.
        cur.execute("SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS c "
                    "WHERE c.TABLE_SCHEMA = 'Input' AND c.TABLE_NAME = ? "
                    "  AND COLUMNPROPERTY(OBJECT_ID('Input.' + c.TABLE_NAME), c.COLUMN_NAME,"
                    "                     'IsComputed') = 0", t)
        live = {r[0]: r[1] for r in cur.fetchall()}
        missing = [c for c in cols if c not in live]
        if missing:
            raise SystemExit('REFUSING: Input.%s no longer has %s. Reverse the schema change first.'
                             % (t, ', '.join(missing)))
        added = [c for c in live if c not in cols]
        if added:
            print('  note: Input.%s has gained %s since the export; it will be left to its default.'
                  % (t, ', '.join(added)))

        cur.execute('SELECT COUNT(*) FROM [Input].[%s]' % t)
        before = cur.fetchone()[0]
        print('  %-22s live %6d  ->  backup %6d' % (t, before, meta['rows']))
        if dry:
            continue

        # ==> ALL OR NOTHING. <== DELETE and INSERT commit together, so an interrupted restore
        # cannot leave the table holding half of each generation -- which for targets would be
        # indistinguishable from someone having edited them.
        rows = [[_typed(v, live[c]) for v, c in zip(r, cols)] for r in data['rows']]
        cur.execute('DELETE FROM [Input].[%s]' % t)
        if rows:
            cur.fast_executemany = True
            cur.executemany(
                'INSERT INTO [Input].[%s] (%s) VALUES (%s)'
                % (t, ', '.join('[%s]' % c for c in cols), ', '.join('?' * len(cols))), rows)
        cn.commit()

        cur.execute('SELECT COUNT(*) FROM [Input].[%s]' % t)
        after = cur.fetchone()[0]
        if after != meta['rows']:
            raise SystemExit('RESTORE FAILED: Input.%s holds %d, backup had %d.'
                             % (t, after, meta['rows']))
        print('  %-22s restored %d row(s)' % (t, after))

    cn.close()
    print('\n%s' % ('dry run -- nothing written' if dry else 'done'))


if __name__ == '__main__':
    main()
