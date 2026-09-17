"""Copy AppDB Input.* (Azure SQL) into WH_Dentally.Input_Stage.*, then run the sync procs.

Runs as a Container Apps Job, not a Fabric notebook. AppDB moved off the Fabric capacity to
Azure SQL because the Fabric SQL Database endpoint kept hanging (AppDB/MIGRATION.md); routing the
copy through Fabric compute would have put the dependency straight back, and would have needed an
allow-all-Azure rule on the SQL firewall because Fabric egress IPs are dynamic. The Container Apps
environment has a static egress IP that is already allowed, so this needs no firewall change and
the 10-minute access sync no longer depends on the capacity being healthy.

Replaces the three-part cross-database read the procs used to do:
    [AppDB].[Input].[Application_Users]   ->   Input_Stage.Application_Users

Modes:
    python appdb_sync.py access   # Application_Users + Access_Log, then usp_Sync_Access_From_AppDB
    python appdb_sync.py full     # all eight tables, then usp_Sync_Input_From_AppDB
    python appdb_sync.py copy     # all eight tables, run NO proc -- for validating a cutover
    python appdb_sync.py check    # copy nothing, just report both sides

Connection settings come from the same env vars the app uses, so the job inherits the container's
configuration and cannot drift from it.
"""
import os
import struct
import sys

import msal
import pyodbc

# Deliberately NOT importing Web/app.py: that boots Flask, reads a dozen required env vars and
# opens Key Vault. These few lines are duplicated instead of coupling a batch job to the web app.
TENANT_ID     = os.environ['TENANT_ID']
CLIENT_ID     = os.environ.get('AZURE_CLIENT_ID',     os.environ['CLIENT_ID'])
CLIENT_SECRET = os.environ.get('AZURE_CLIENT_SECRET', os.environ['CLIENT_SECRET'])
APPDB_SERVER  = os.environ['APPDB_SERVER']
APPDB_DB      = os.environ['APPDB_DB']
FABRIC_SERVER = os.environ['FABRIC_SERVER']
FABRIC_DB     = os.environ['FABRIC_DB']

ACCESS_TABLES = ['Application_Users', 'Access_Log']
FULL_TABLES   = ACCESS_TABLES + ['Metric_Variance', 'Plan_Capitation_Rate', 'Practice_Config',
                                 'Practitioner_Pay', 'Practitioner_Role', 'Targets']

# A source table that has gone unexpectedly empty is the one input that could do real harm, so
# refuse to proceed below these floors rather than sync an empty roster. Application_Users empty
# would mean nobody has access; Targets empty would blank every target fact.
NONEMPTY = {'Application_Users': 1, 'Targets': 1}

_msal_app = None


def _token_struct():
    """Entra token for SQL, as the app's own service principal -- the same identity that already
    reads the warehouse and AppDB, so no new principal to manage."""
    global _msal_app
    if _msal_app is None:
        _msal_app = msal.ConfidentialClientApplication(
            CLIENT_ID, authority=f'https://login.microsoftonline.com/{TENANT_ID}',
            client_credential=CLIENT_SECRET)
    r = _msal_app.acquire_token_for_client(scopes=['https://database.windows.net//.default'])
    if 'access_token' not in r:
        raise RuntimeError(r.get('error_description', 'token acquisition failed'))
    tb = r['access_token'].encode('utf-16-le')
    return struct.pack(f'<I{len(tb)}s', len(tb), tb)


def _connect(server, database, tok):
    cs = (f'Driver={{ODBC Driver 18 for SQL Server}};Server={server},1433;'
          f'Database={database};Encrypt=yes;TrustServerCertificate=no;Login Timeout=30;')
    return pyodbc.connect(cs, attrs_before={1256: tok}, autocommit=True)


def _count(cur, schema, table):
    cur.execute(f'SELECT COUNT(*) FROM [{schema}].[{table}]')
    return cur.fetchone()[0]


def _columns(cur, schema, table):
    """Column list from the TARGET, so a column the warehouse staging lacks is never sent."""
    cur.execute('SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS '
                'WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION',
                schema, table)
    return [r[0] for r in cur.fetchall()]


def copy_tables(src, tgt, tables):
    """Copy each table, then verify counts. Returns {table: (source, staged)}.

    Rows are batched into multi-row INSERTs: the Fabric Warehouse is columnstore and a per-row
    INSERT costs roughly as much as a 100-row one, so single-row inserts would turn 750 rows into
    minutes of work.
    """
    result = {}
    for t in tables:
        cols = _columns(tgt, 'Input_Stage', t)
        if not cols:
            raise RuntimeError(f'Input_Stage.{t} does not exist in {FABRIC_DB} -- deploy the DDL first')
        collist = ', '.join(f'[{c}]' for c in cols)

        src.execute(f'SELECT {collist} FROM [Input].[{t}]')
        rows = [tuple(r) for r in src.fetchall()]
        n_src = len(rows)
        if n_src < NONEMPTY.get(t, 0):
            raise RuntimeError(
                f'REFUSING to sync: source Input.{t} has {n_src} rows, expected at least '
                f'{NONEMPTY[t]}. An empty source here would wipe downstream state, so this is '
                f'treated as a fault rather than a legitimate empty table.')

        tgt.execute(f'DELETE FROM [Input_Stage].[{t}]')
        marks = '(' + ', '.join(['?'] * len(cols)) + ')'
        BATCH = 100
        for i in range(0, n_src, BATCH):
            chunk = rows[i:i + BATCH]
            tgt.execute(
                f'INSERT INTO [Input_Stage].[{t}] ({collist}) VALUES ' + ', '.join([marks] * len(chunk)),
                [v for r in chunk for v in r])

        staged = _count(tgt, 'Input_Stage', t)
        result[t] = (n_src, staged)
        print(f'  {t:24} {n_src:>6} -> {staged:>6} {"OK" if n_src == staged else "MISMATCH"}')
    return result


def main():
    mode = (sys.argv[1] if len(sys.argv) > 1 else 'check').lower()
    if mode not in ('access', 'full', 'copy', 'check'):
        print(__doc__)
        return 2

    tables = ACCESS_TABLES if mode == 'access' else FULL_TABLES
    tok = _token_struct()
    src_cn = _connect(APPDB_SERVER, APPDB_DB, tok)
    tgt_cn = _connect(FABRIC_SERVER, FABRIC_DB, tok)
    src, tgt = src_cn.cursor(), tgt_cn.cursor()
    print(f'appdb-sync [{mode}]  {APPDB_DB} -> {FABRIC_DB}.Input_Stage')

    if mode == 'check':
        for t in FULL_TABLES:
            try:
                print(f'  {t:24} source {_count(src, "Input", t):>6}   '
                      f'staged {_count(tgt, "Input_Stage", t):>6}')
            except Exception as e:
                print(f'  {t:24} {str(e)[:70]}')
        return 0

    counts = copy_tables(src, tgt, tables)
    bad = [t for t, (a, b) in counts.items() if a != b]
    if bad:
        # Do NOT run the procs on a partial copy. They MERGE from staging, so a half-filled
        # table would look like a legitimate change set and quietly write the wrong state.
        raise RuntimeError(f'row counts differ for {", ".join(bad)} -- procs NOT run')

    if mode == 'copy':
        # Staging filled, nothing executed. Used to prove the copy against the old Fabric source
        # before V161 repoints the procs -- the whole point being to compare, not to act.
        print('copy-only: staging filled, no proc run')
        src_cn.close(); tgt_cn.close()
        return 0

    proc = ('Meta.usp_Sync_Access_From_AppDB' if mode == 'access'
            else 'Meta.usp_Sync_Input_From_AppDB')
    before = _count(tgt, 'Security', 'Application_Users') if mode == 'access' else None
    tgt.execute('DECLARE @i BIGINT, @u BIGINT, @d BIGINT; '
                f'EXEC {proc} @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;')
    if mode == 'access':
        after = _count(tgt, 'Security', 'Application_Users')
        print(f'{proc}: Security.Application_Users {before} -> {after}')
    else:
        print(f'{proc}: done')

    src_cn.close()
    tgt_cn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
