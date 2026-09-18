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
    python appdb_sync.py access   # stage all, then usp_Sync_Access_From_AppDB   (10-minute job)
    python appdb_sync.py full     # stage all, then usp_Sync_Input_From_AppDB    (nightly build)
    python appdb_sync.py copy     # stage all, run NO proc -- for validating a cutover
    python appdb_sync.py check    # copy nothing, just report both sides

Every mode stages all eight tables; the mode only chooses which proc runs afterwards.

Connection settings come from the same env vars the app uses, so the job inherits the container's
configuration and cannot drift from it.

ON FAILURE IT EMAILS, ITSELF -- see the GRAPH_SEND block below. Azure Monitor's alert rules fire
here but never deliver mail, and this carries the actual error rather than just "an execution
failed". Transitions only, plus a reminder every ALERT_REPEAT_HOURS while it stays broken.
"""
import os
import struct
import sys
import uuid
from datetime import datetime, timezone

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

# THIS JOB EMAILS ITS OWN FAILURES, because Azure Monitor does not. Its alert rules fire correctly
# -- observed firing and resolving, isSuppressed false, action group attached and enabled, both
# receivers verified -- and no email is ever delivered. A manual TEST notification to the same
# action group arrives within a minute, so the mailbox and the address are fine; only the
# alert-to-email path is broken, and nothing in the configuration explains it.
#
# Sending from here is better anyway. Azure Monitor could only ever say "an execution failed": it
# watches the exit code. This knows WHICH step failed and carries the actual error, and it sends on
# the first failure instead of waiting for a 5-minute evaluation over a 15-minute window.
#
# Same Graph path the web app already uses to reach this mailbox, with the same credentials this
# job already holds for SQL -- no new secret, no new app permission.
APP_ENV       = os.environ.get('APP_ENV') or ('prod' if APPDB_DB.endswith('prod') else 'dev')
GRAPH_SEND    = os.environ.get('GRAPH_SEND', '').strip().lower() in ('1', 'true', 'yes', 'on')
GRAPH_FROM    = os.environ.get('GRAPH_FROM', 'support@analytically.info')
ALERT_TO      = [a.strip() for a in os.environ.get(
                     'ALERT_TO', 'support@analytically.info').split(',') if a.strip()]
# While a failure persists, repeat the alert this often. Azure Monitor sends once per transition and
# never again, which is the behaviour that loses you a whole weekend if the one email goes astray.
ALERT_REPEAT_HOURS = float(os.environ.get('ALERT_REPEAT_HOURS', '6'))

FULL_TABLES = ['Application_Users', 'Access_Log', 'Metric_Variance', 'Plan_Capitation_Rate',
               'Practice_Config', 'Practitioner_Pay', 'Practitioner_Role', 'Targets']

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


def _graph_token():
    """Graph token for sendMail, as the service principal this job already runs as.

    Deliberately a second MSAL client rather than reusing _msal_app: that one is cached holding a
    SQL-scoped token, and asking it for a Graph scope would evict a token the sync still needs.
    """
    app = msal.ConfidentialClientApplication(
        CLIENT_ID, authority=f'https://login.microsoftonline.com/{TENANT_ID}',
        client_credential=CLIENT_SECRET)
    r = app.acquire_token_for_client(scopes=['https://graph.microsoft.com/.default'])
    if 'access_token' not in r:
        raise RuntimeError(r.get('error_description', 'Graph token acquisition failed'))
    return r['access_token']


def _send_alert_email(subject, body):
    """Send one operational alert. Returns True if sent.

    NO NON-PROD REDIRECT, unlike the web app's mailer. That redirect exists to stop dev emailing a
    real dental practice, because dev's tenant 100 is a copy of a live one. This only ever writes to
    our own mailbox, and a dev sync failing is exactly as worth knowing about as a prod one -- the
    two environments share a Fabric capacity, so dev usually fails first.
    """
    if not GRAPH_SEND:
        print('ALERT (not sent -- GRAPH_SEND is off):\n  ' + subject)
        return False
    import requests
    r = requests.post(
        f'https://graph.microsoft.com/v1.0/users/{GRAPH_FROM}/sendMail',
        headers={'Authorization': 'Bearer ' + _graph_token(), 'Content-Type': 'application/json'},
        json={'message': {'subject': subject,
                          'body': {'contentType': 'Text', 'content': body},
                          'toRecipients': [{'emailAddress': {'address': a}} for a in ALERT_TO]},
              'saveToSentItems': False},
        timeout=30)
    r.raise_for_status()
    return True


def _alert_decision(cur, process, started, status):
    """Should this run email, and as what? Returns (kind, detail) with kind in
    'failed' | 'recovered' | None.

    MODELLED ON TRANSITIONS, not on every run. The access job runs every ten minutes: emailing each
    failure would send 144 a day, which trains you to filter it and is worse than silence. So:
    the first failure after a success, the first success after a failure, and -- unlike Azure
    Monitor -- a reminder every ALERT_REPEAT_HOURS while it stays broken, so a single lost email
    cannot cost you the outage.

    Reads only rows STRICTLY OLDER than this run (Start_Time < started), so it does not matter
    whether the current run has already been logged.
    """
    cur.execute(
        "SELECT TOP 40 Status, Start_Time FROM Audit.Process_Execution_Log "
        "WHERE Process_Name = ? AND Start_Time < ? ORDER BY Start_Time DESC", process, started)
    history = [(r[0] or '', r[1]) for r in cur.fetchall()]

    if status == 'SUCCEEDED':
        if history and history[0][0] == 'FAILED':
            return 'recovered', f'after {_streak_len(history)} failed run(s)'
        return None, None

    if not history or history[0][0] != 'FAILED':
        return 'failed', 'first failure'

    # Still failing. Repeat only when the outage crosses another ALERT_REPEAT_HOURS boundary --
    # computed from the streak's start, so it needs no record of when we last emailed.
    n = _streak_len(history)
    streak_start = history[n - 1][1]
    if ALERT_REPEAT_HOURS <= 0 or streak_start is None:
        return None, None
    now_h  = (started - streak_start).total_seconds() / 3600.0
    prev_h = (history[0][1] - streak_start).total_seconds() / 3600.0
    if int(now_h // ALERT_REPEAT_HOURS) > int(prev_h // ALERT_REPEAT_HOURS):
        return 'failed', f'still failing after {now_h:.1f}h ({n + 1} runs)'
    return None, None


def _streak_len(history):
    """How many consecutive FAILED runs at the head of the history."""
    n = 0
    for st, _ in history:
        if st != 'FAILED':
            break
        n += 1
    return n


def _alert(tgt_cn, mode, started, status, error=None):
    """Decide and send. BEST EFFORT, for the same reason _log_run is.

    An alerting failure must never replace the real error in the traceback, or we go hunting a mail
    problem while the sync stays broken. If the warehouse cannot be read to work out whether this is
    a transition, it FAILS OPEN and emails anyway: a duplicate is a nuisance, a missed outage is the
    thing this exists to prevent.
    """
    process = 'appdb_sync.' + mode
    try:
        kind, detail = None, None
        try:
            kind, detail = _alert_decision(tgt_cn.cursor(), process, started, status)
        except Exception as e:
            if status == 'FAILED':
                kind, detail = 'failed', f'(could not read run history: {str(e)[:120]})'
            else:
                raise
        if kind is None:
            return

        where = f'{APP_ENV} / {mode}'
        if kind == 'recovered':
            subject = f'[{APP_ENV}] AppDB sync RECOVERED ({mode})'
            body = (f'The AppDB sync is working again.\n\n'
                    f'  environment : {where}\n'
                    f'  recovered   : {started:%Y-%m-%d %H:%M} UTC\n'
                    f'  context     : {detail}\n')
        else:
            subject = f'[{APP_ENV}] AppDB sync FAILED ({mode})'
            body = (f'The AppDB sync failed. Access changes and target edits are NOT reaching the '
                    f'warehouse until this is fixed.\n\n'
                    f'  environment : {where}\n'
                    f'  job         : caj-appdb-sync-{APP_ENV}\n'
                    f'  source      : {APPDB_SERVER} / {APPDB_DB}\n'
                    f'  target      : {FABRIC_DB}.Input_Stage\n'
                    f'  failed at   : {started:%Y-%m-%d %H:%M} UTC\n'
                    f'  context     : {detail}\n\n'
                    f'  error       : {str(error)[:3000]}\n')
        _send_alert_email(subject, body)
        print(f'alert sent ({kind}) to {", ".join(ALERT_TO)}')
    except Exception as e:                                  # noqa: BLE001 -- see docstring
        print('WARNING: could not send the alert email: ' + str(e)[:300])


def _log_run(tgt_cn, mode, started, status, error=None, rows=None):
    """Write one Audit.Process_Execution_Log row so this job is visible where every other process
    already is -- the monitor emails FAILED rows from that table, so there is nothing new to build.

    BEST EFFORT, AND DELIBERATELY SO. The table lives in the warehouse, on the Fabric capacity, so
    the one failure this most needs to report -- the capacity being down, which is the whole reason
    AppDB moved off it -- is exactly the one it cannot record. Any error here is swallowed: it must
    never replace the real error in the traceback, or a logging failure would masquerade as a sync
    failure and send us chasing the wrong thing.

    This covers the common case (warehouse fine, Azure SQL or the proc unhappy). The
    capacity-is-down case is covered by the job's NON-ZERO EXIT, which Azure records and an Azure
    Monitor alert rule can act on without touching Fabric at all. Do not mistake this row for
    complete coverage.
    """
    own = None
    try:
        if tgt_cn is None:
            # AppDB unreachable is the commonest failure, and it happens before any connection
            # exists -- so open one purely to log, or this records nothing at all.
            own = _connect(FABRIC_SERVER, FABRIC_DB, _token_struct())
            tgt_cn = own
        cur  = tgt_cn.cursor()
        now  = datetime.now(timezone.utc).replace(tzinfo=None)
        cur.execute(
            "INSERT INTO Audit.Process_Execution_Log "
            "(Run_UUID, Process_Name, Process_Type, Start_Time, End_Time, Duration_Seconds, "
            " Num_Of_Records, Status, Error_Message, Database_Name, Executed_By, Run_Date, "
            " Process_Options) "
            "VALUES (?, ?, 'JOB', ?, ?, ?, ?, ?, ?, ?, 'caj-appdb-sync', ?, ?)",
            str(uuid.uuid4()), 'appdb_sync.' + mode, started, now,
            (now - started).total_seconds(), rows, status,
            (str(error)[:8000] if error else None), APPDB_DB,
            now.date(), 'mode=' + mode)
    except Exception as e:                                  # noqa: BLE001 -- see docstring
        print('WARNING: could not write Audit.Process_Execution_Log: ' + str(e)[:200])
    finally:
        if own is not None:
            try:
                own.close()
            except Exception:
                pass


def main():
    mode = (sys.argv[1] if len(sys.argv) > 1 else 'check').lower()
    if mode not in ('access', 'full', 'copy', 'check'):
        print(__doc__)
        return 2

    # ALWAYS stage all eight, whichever proc is being run. Staging only two would leave the
    # nightly META_SYNC_INPUT reading a stale copy of the other six, and make correctness depend
    # on job ordering. The whole dataset is ~750 rows, so there is nothing to save by being clever.
    tables = FULL_TABLES
    started = datetime.now(timezone.utc).replace(tzinfo=None)
    src_cn = tgt_cn = None
    try:
        tok = _token_struct()
        src_cn = _connect(APPDB_SERVER, APPDB_DB, tok)
        tgt_cn = _connect(FABRIC_SERVER, FABRIC_DB, tok)
    except Exception as e:
        # Covers the case this job exists to survive: AppDB unreachable. _log_run opens its own
        # warehouse connection, so this still lands in the monitor as long as the CAPACITY is up.
        if mode != 'check':
            _log_run(tgt_cn, mode, started, 'FAILED', error=e)
            _alert(tgt_cn, mode, started, 'FAILED', error=e)
        raise
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

    try:
        return _run(mode, tables, src, tgt, src_cn, tgt_cn, started)
    except Exception as e:
        # Log, then re-raise unchanged: the job must still exit non-zero, because that exit is the
        # only failure signal that does not depend on the Fabric capacity.
        _log_run(tgt_cn, mode, started, 'FAILED', error=e)
        _alert(tgt_cn, mode, started, 'FAILED', error=e)
        raise


def _run(mode, tables, src, tgt, src_cn, tgt_cn, started):
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
        _log_run(tgt_cn, mode, started, 'SUCCEEDED', rows=sum(a for a, _ in counts.values()))
        _alert(tgt_cn, mode, started, 'SUCCEEDED')
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

    _log_run(tgt_cn, mode, started, 'SUCCEEDED', rows=sum(a for a, _ in counts.values()))
    _alert(tgt_cn, mode, started, 'SUCCEEDED')
    src_cn.close()
    tgt_cn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
