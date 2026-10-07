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
import hashlib
import json
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

# Sentinel row in Input_Stage.Sync_Fingerprint recording when the access proc last actually ran.
# Not a table name, so it can never collide with one of FULL_TABLES.
PROC_SENTINEL = '(access proc)'
# Two more sentinels, used only in the AppDB cache (Input.Sync_State). Same no-collision reasoning.
COLS_SENTINEL = '(columns)'          # Payload = JSON {table: [column, ...]} for Input_Stage
STATUS_SENTINEL = '(last status)'    # outcome of the previous access run
FORCE_SENTINEL = '(last full restage)'   # when every table was last rewritten unconditionally

# ==> SOMETHING MUST REWRITE Input_Stage UNCONDITIONALLY, OR A BAD COPY IS PERMANENT. <== The
# fingerprint skip is only safe while staging is known to match source. If staging were edited
# directly, or a write half-failed in a way that left the fingerprint looking right, nothing would
# ever correct it -- the comparison would match forever. _run's comment has always claimed a nightly
# full sync re-established truth; there is no such job, so the access run does it itself this often.
FORCE_MAX_AGE_HOURS = float(os.environ.get('FORCE_MAX_AGE_HOURS', '20'))
# Run the access proc at least this often even when nothing has changed, so that no mistake in the
# skip logic can stop the merge for longer than this.
PROC_MAX_SKIP_MINUTES = float(os.environ.get('PROC_MAX_SKIP_MINUTES', '60'))

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


def _columns_bulk(tgt, schema, tables):
    """Every table's column list in ONE round trip, ordered as the table declares them.

    Eight INFORMATION_SCHEMA queries used to be eight distributed statements on the warehouse,
    every ten minutes, before a single row had been looked at. The whole point of this job is to
    be free when nothing has changed, and eight statements is not free.
    """
    marks = ', '.join(['?'] * len(tables))
    tgt.execute(
        'SELECT TABLE_NAME, COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS '
        f'WHERE TABLE_SCHEMA = ? AND TABLE_NAME IN ({marks}) '
        'ORDER BY TABLE_NAME, ORDINAL_POSITION', [schema] + list(tables))
    out = {}
    for tname, cname in tgt.fetchall():
        out.setdefault(tname, []).append(cname)
    return out


def _fingerprint(rows):
    """A stable digest of a table's contents.

    Sorted before hashing because the source SELECT carries no ORDER BY, so row order is not
    guaranteed between runs and an order change is not a content change.

    Each field is tagged 'N' for NULL or 'V' before its value, then NUL joins fields and RS joins
    rows. Both parts are load-bearing: without the separators ('a','b') and ('ab',) hash alike,
    and without the tag NULL and '' do -- which the test suite caught in the first version of
    this, where a UPN edited from NULL to empty would have read as unchanged and never restaged.
    """
    parts = sorted('\x00'.join('N' if v is None else 'V' + str(v) for v in r) for r in rows)
    return hashlib.sha256('\x1e'.join(parts).encode('utf-8')).hexdigest()


def _stored_fingerprints(tgt):
    """What each staged table held when it was last written. One round trip, empty on first run."""
    try:
        tgt.execute('SELECT Table_Name, Row_Count, Fingerprint FROM [Input_Stage].[Sync_Fingerprint]')
        return {r[0]: (r[1], r[2]) for r in tgt.fetchall()}
    except Exception as e:
        # Missing table on first deploy must not break the sync -- it just means nothing can be
        # skipped yet, which is the safe direction.
        print(f'  (no fingerprint table yet: {str(e)[:60]} -- copying everything)')
        return {}


def copy_tables(src, tgt, tables, force=False):
    """Copy each table that has CHANGED, then verify counts. Returns {table: (source, staged)}.

    ==> ACCESS RECORDS ALMOST NEVER CHANGE, SO THIS JOB SHOULD ALMOST NEVER WRITE. <==
    It used to DELETE and re-INSERT all eight tables on every run. At one run per ten minutes that
    was 1,000 runs and ~84 statements each in a week -- 6,422 CPU-seconds, 32% of the production
    warehouse's entire compute, to restage roughly 750 rows that were already identical.

    The source read is free: AppDB is Azure SQL, billed on provisioned capacity rather than per
    statement. So the rows are fetched, fingerprinted in Python, and compared with what was staged
    last time. Unchanged tables are not touched at all.

    ==> STAGING STILL MATCHES SOURCE AFTER EVERY RUN. <== That invariant is what lets main() stage
    all eight tables regardless of mode; skipping a write when the content is provably identical
    does not weaken it. `force` restores unconditional rewriting for the nightly full sync, which
    is the anchor that re-establishes truth even if something edited Input_Stage directly.
    """
    result = {}
    changed = set()
    fps = {}        # {table: (rows, fingerprint)} for the AppDB mirror
    colmap = _columns_bulk(tgt, 'Input_Stage', tables)
    stored = {} if force else _stored_fingerprints(tgt)
    for t in tables:
        cols = colmap.get(t)
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

        fp = _fingerprint(rows)
        fps[t] = (n_src, fp)
        was = stored.get(t)
        if was and was[0] == n_src and was[1] == fp:
            # Nothing written, and deliberately not re-counted: the count would be another
            # statement to confirm something the fingerprint already establishes.
            result[t] = (n_src, n_src)
            print(f'  {t:24} {n_src:>6}    unchanged')
            continue

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
        changed.add(t)
        print(f'  {t:24} {n_src:>6} -> {staged:>6} {"OK" if n_src == staged else "MISMATCH"}')

        # Recorded only after a verified write, so a mismatch cannot be skipped next time round.
        if n_src == staged:
            tgt.execute('DELETE FROM [Input_Stage].[Sync_Fingerprint] WHERE Table_Name = ?', t)
            tgt.execute(
                'INSERT INTO [Input_Stage].[Sync_Fingerprint] '
                '(Table_Name, Row_Count, Fingerprint, Updated_At) VALUES (?, ?, ?, SYSUTCDATETIME())',
                t, n_src, fp)
    return result, changed, fps, colmap


def _note_proc_ran(tgt):
    """Record that the access proc actually ran, in the fingerprint table's sentinel row.

    Kept here rather than in its own table because _stored_fingerprints already reads this table
    in one round trip, and the whole point of the exercise is to stop spending statements.
    """
    tgt.execute('DELETE FROM [Input_Stage].[Sync_Fingerprint] WHERE Table_Name = ?', PROC_SENTINEL)
    tgt.execute(
        'INSERT INTO [Input_Stage].[Sync_Fingerprint] '
        '(Table_Name, Row_Count, Fingerprint, Updated_At) VALUES (?, 0, ?, SYSUTCDATETIME())',
        PROC_SENTINEL, '0' * 64)


def _why_run_proc(tgt, changed, started):
    """Reason to run Meta.usp_Sync_Access_From_AppDB, or None to skip it.

    ==> STAGING NOT CHANGING IS NOT QUITE ENOUGH TO SKIP THE MERGE. <== It would be if the only
    way Security.Application_Users could drift were through staging, but a failed proc run leaves
    staging correct and the target half-written, and skipping on "nothing changed" would then
    preserve that state indefinitely. So two other things also force a run.

    This is what was left after V199: the copy stopped writing, and the consumer kept merging
    every ten minutes regardless -- about 49 statements and 1.15 CPU-seconds a run, ~165 a day.
    """
    if changed:
        return 'staging changed: ' + ', '.join(sorted(changed))

    # A previous failure must not be made permanent by a run that decides there is nothing to do.
    tgt.execute(
        "SELECT TOP 1 Status FROM Audit.Process_Execution_Log "
        "WHERE Process_Name = 'appdb_sync.access' AND Start_Time < ? ORDER BY Start_Time DESC",
        started)
    row = tgt.fetchone()
    if row and (row[0] or '').upper() != 'SUCCEEDED':
        return f'previous run was {row[0]}'

    # Self-heal: run it occasionally whatever the fingerprints say, so no reasoning error here can
    # stop the merge for longer than this window.
    tgt.execute(
        'SELECT Updated_At FROM [Input_Stage].[Sync_Fingerprint] WHERE Table_Name = ?',
        PROC_SENTINEL)
    row = tgt.fetchone()
    if not row:
        return 'no record of the proc having run'
    age_min = (datetime.now(timezone.utc).replace(tzinfo=None) - row[0]).total_seconds() / 60.0
    if age_min >= PROC_MAX_SKIP_MINUTES:
        return f'last ran {age_min:.0f} min ago (self-heal at {PROC_MAX_SKIP_MINUTES:.0f})'
    return None



# ==================================================================================================
# The fast path. See Migrations/V153__sync_state_in_appdb.sql for why this exists.
# ==================================================================================================
def _local_state(src):
    """Everything the skip decision needs, from AppDB, in one round trip. {} if unavailable."""
    try:
        src.execute('SELECT Item, Row_Count, Fingerprint, Payload, Updated_At FROM [Input].[Sync_State]')
        return {r[0]: (r[1], r[2], r[3], r[4]) for r in src.fetchall()}
    except Exception as e:
        # Missing table (first deploy, or V153 not applied) must not break the sync -- it just
        # means nothing can be skipped yet, which is the safe direction.
        print(f'  (no local sync state: {str(e)[:60]} -- using the Fabric path)')
        return {}


def _save_local(src, item, row_count=None, fingerprint=None, payload=None):
    """Upsert one row of the cache. Separate statements rather than MERGE: AppDB is Azure SQL and
    these are free, and MERGE has enough sharp edges to be worth avoiding for two writes."""
    src.execute('DELETE FROM [Input].[Sync_State] WHERE Item = ?', item)
    src.execute(
        'INSERT INTO [Input].[Sync_State] (Item, Row_Count, Fingerprint, Payload, Updated_At) '
        'VALUES (?, ?, ?, ?, SYSUTCDATETIME())', item, row_count, fingerprint, payload)


def _mirror_local(src, fps, colmap, status, forced=False):
    """Write the cache in the same breath as the warehouse copy it mirrors.

    Called only after a run that actually reached the warehouse, so the cache can never claim a
    state the warehouse has not reached.
    """
    try:
        for t, (n, fp) in fps.items():
            _save_local(src, t, row_count=n, fingerprint=fp)
        if forced:
            # Written only here, after a verified rewrite of every table, so a failure part way
            # through leaves the restage due rather than marking it done.
            _save_local(src, FORCE_SENTINEL, fingerprint='forced')
        _save_local(src, COLS_SENTINEL, payload=json.dumps(colmap, sort_keys=True))
        _save_local(src, STATUS_SENTINEL, fingerprint=status)
    except Exception as e:
        # The cache is an optimisation. Failing to write it must never fail the sync -- the next
        # run simply takes the Fabric path, which is what happens today anyway.
        print(f'  (could not write local sync state: {str(e)[:80]})')


def _restage_due(src, started):
    """Is a forced rewrite of Input_Stage overdue? Unknown or out-of-range means yes.

    Deliberately pessimistic: a missing sentinel (first run after this ships, cache cleared) forces
    a restage, which costs one ordinary slow run and re-establishes the invariant the skip logic
    depends on.
    """
    try:
        src.execute('SELECT Updated_At FROM [Input].[Sync_State] WHERE Item = ?', FORCE_SENTINEL)
        row = src.fetchone()
    except Exception:
        return True
    if not row or not row[0]:
        return True
    age_h = (started - row[0]).total_seconds() / 3600.0
    return age_h < 0 or age_h >= FORCE_MAX_AGE_HOURS


def _fast_skip(src, started):
    """Reason to skip this access run entirely, or None to go the full Fabric route.

    ==> EVERY UNCERTAINTY RETURNS None. <== Missing cache, unparseable column map, a table the map
    does not cover, an unreadable source, a previous failure, a stale proc sentinel -- all fall
    through to the Fabric path. The worst case of this function is the behaviour we had before it.

    It reproduces exactly the three conditions _why_run_proc applies, against the AppDB mirror
    rather than the warehouse, so the two cannot disagree about what "nothing to do" means.
    """
    state = _local_state(src)
    if not state:
        return None

    cols_row = state.get(COLS_SENTINEL)
    if not cols_row or not cols_row[2]:
        return None
    try:
        colmap = json.loads(cols_row[2])
    except Exception:
        return None

    # A previous failure must not be made permanent by a run that decides there is nothing to do.
    st = state.get(STATUS_SENTINEL)
    if not st or (st[1] or '').upper() != 'SUCCEEDED':
        return None

    # Self-heal: the merge must run at least this often whatever the fingerprints say.
    proc = state.get(PROC_SENTINEL)
    if not proc or not proc[3]:
        return None
    age_min = (started - proc[3]).total_seconds() / 60.0
    # ==> NEGATIVE MEANS THE SENTINEL IS IN THE FUTURE, AND THAT MUST NOT GRANT A SKIP. <== AppDB
    # stamps it with SYSUTCDATETIME() and this job runs on a different host; any clock skew the
    # wrong way would otherwise sail past the >= below and skip for as long as the skew lasts.
    # Out of range in either direction means the state is not trustworthy, so take the Fabric path.
    if age_min < 0 or age_min >= PROC_MAX_SKIP_MINUTES:
        return None

    # A restage that is due outranks "nothing changed" -- the whole point is that it runs even
    # when the fingerprints agree, because the fingerprints are what it exists to re-prove.
    forced = state.get(FORCE_SENTINEL)
    if not forced or not forced[3]:
        return None
    force_age_h = (started - forced[3]).total_seconds() / 3600.0
    if force_age_h < 0 or force_age_h >= FORCE_MAX_AGE_HOURS:
        return None

    # Only now read the source, and only to prove it is unchanged.
    for t in FULL_TABLES:
        cols = colmap.get(t)
        if not cols:
            return None
        was = state.get(t)
        if not was:
            return None
        try:
            src.execute('SELECT ' + ', '.join(f'[{c}]' for c in cols) + f' FROM [Input].[{t}]')
            rows = [tuple(r) for r in src.fetchall()]
        except Exception:
            return None
        if len(rows) < NONEMPTY.get(t, 0):
            return None                      # let the Fabric path raise the real error
        if was[0] != len(rows) or was[1] != _fingerprint(rows):
            return None

    return (f'nothing to do: all {len(FULL_TABLES)} tables unchanged, last merge '
            f'{age_min:.0f} min ago -- no Fabric session opened')


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
    own = None
    try:
        kind, detail = None, None
        try:
            cn = tgt_cn
            if cn is None:
                # AppDB unreachable -- the commonest failure, and the one this job exists to
                # survive -- throws before tgt_cn is ever assigned, so open a connection purely to
                # read the history. WITHOUT THIS the decision blew up on None.cursor(), the
                # fail-open below caught it, and every single attempt emailed: four identical
                # alerts from one broken run (two executions x replicaRetryLimit 1). Dedup never
                # ran on the one failure mode it was needed for.
                own = cn = _connect(FABRIC_SERVER, FABRIC_DB, _token_struct())
            kind, detail = _alert_decision(cn.cursor(), process, started, status)
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
        # ==> REPORT WHAT HAPPENED, NOT WHAT WAS ATTEMPTED. <== _send_alert_email returns False
        # when GRAPH_SEND is off, which is the normal case for a manual run from a workstation.
        # Printing "alert sent" regardless made a local run look like it had emailed the support
        # mailbox -- it misled a reader into reporting two spurious alerts on 2026-10-02. The
        # deployed container apps both set GRAPH_SEND=1, so this only ever affected manual runs,
        # but a log line that claims an alert was sent is the last thing that should be guessed at.
        if _send_alert_email(subject, body):
            print(f'alert sent ({kind}) to {", ".join(ALERT_TO)}')
        else:
            print(f'alert NOT sent ({kind}) -- GRAPH_SEND is off in this environment')
    except Exception as e:                                  # noqa: BLE001 -- see docstring
        print('WARNING: could not send the alert email: ' + str(e)[:300])
    finally:
        if own is not None:
            try:
                own.close()
            except Exception:
                pass


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
        # ==> THE WHOLE POINT: DECIDE BEFORE CONNECTING TO FABRIC. <== 4,015 of 4,015 runs over
        # 14 days had nothing to do, and each one opened a warehouse session to find that out.
        # Everything the decision needs is mirrored in AppDB, which is not billed per statement.
        if mode == 'access':
            why_not = _fast_skip(src_cn.cursor(), started)
            if why_not:
                print(f'appdb-sync [access]  {why_not}')
                src_cn.close()
                return 0
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
    # The access job skips tables whose contents are provably identical. That is only safe while
    # staging is known to match source, so something must rewrite it unconditionally from time to
    # time -- otherwise a staging table edited directly, or left half-written in a way the
    # fingerprint still matches, would never be corrected.
    #
    # ==> THAT USED TO SAY "the nightly full sync does it", AND THERE WAS NO SUCH JOB. <== The only
    # scheduled container jobs are the two `access` ones, and access never passed force. So the
    # access run now forces a restage itself once FORCE_MAX_AGE_HOURS has elapsed; `full` and `copy`
    # still always rewrite.
    # access forces a restage when the last one has aged out; every other mode always forces.
    force_due = (mode == 'access') and _restage_due(src, started)
    if force_due:
        print(f'forcing a full restage: last one over {FORCE_MAX_AGE_HOURS:.0f}h ago')
    counts, changed, fps, colmap = copy_tables(src, tgt, tables,
                                               force=(mode != 'access') or force_due)
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

    # ==> A MERGE FROM STAGING THAT DID NOT MOVE HAS NOTHING TO MERGE. <== V199 stopped the copy
    # rewriting identical rows; the proc went on merging them every ten minutes anyway, which was
    # the ~49 statements and 1.15 CPU-seconds per run still left. _why_run_proc decides, and
    # errs towards running: it only stays quiet when staging is unchanged, the previous run
    # succeeded, and the proc has run recently enough.
    if mode == 'access':
        why = _why_run_proc(tgt, changed, started)
        if why is None:
            print(f'{proc}: skipped -- staging unchanged, last merge within '
                  f'{PROC_MAX_SKIP_MINUTES:.0f} min')
            _mirror_local(src, fps, colmap, 'SUCCEEDED', forced=force_due)
            _log_run(tgt_cn, mode, started, 'SUCCEEDED', rows=sum(a for a, _ in counts.values()))
            _alert(tgt_cn, mode, started, 'SUCCEEDED')
            src_cn.close()
            tgt_cn.close()
            return 0
        print(f'{proc}: running -- {why}')

    before = _count(tgt, 'Security', 'Application_Users') if mode == 'access' else None
    tgt.execute('DECLARE @i BIGINT, @u BIGINT, @d BIGINT; '
                f'EXEC {proc} @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;')
    if mode == 'access':
        after = _count(tgt, 'Security', 'Application_Users')
        print(f'{proc}: Security.Application_Users {before} -> {after}')
        # Written only after the proc returned, so a throw leaves the sentinel stale and the next
        # run is forced rather than skipped.
        _note_proc_ran(tgt)
    else:
        print(f'{proc}: done')

    # Mirror AFTER the proc returned, so the cache can never say "done" for a merge that threw.
    _mirror_local(src, fps, colmap, 'SUCCEEDED', forced=force_due)
    _log_run(tgt_cn, mode, started, 'SUCCEEDED', rows=sum(a for a, _ in counts.values()))
    _alert(tgt_cn, mode, started, 'SUCCEEDED')
    src_cn.close()
    tgt_cn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
