"""Load Sales.Usage_Daily and Sales.Funnel_Event -- the sales monitor's tables.

A SINGLE PLACE for: verification emails sent, keys set up, card supplied, card used, and product
usage. Surfaced through PBI Affiliates (the vendor model), NEVER PBI Dentally -- see
Fabric/Sales.Schema.sql for why absence from the customer model is the control.

    python sales_monitor.py dev|prod [--days 30] [--dry-run]

WHY A LOADER AND NOT A VIEW: three of the five sources are not SQL.

    usage, funnel stages 1-2   Log Analytics (the app's own console lines)
    keys set up                Key Vault, secret onboarding-pending-<env>
    card attached/chargeable   Stripe API                       -- NOT YET, see below
    invoice paid               Billing.Stripe_Invoice           (already SQL)

==> THE CARD STAGES ARE DELIBERATELY NOT IMPLEMENTED. <== There is nothing to read: no
Account_Billing row has a Stripe_Customer_ID, no trial has reached the token step, and
Billing.Stripe_Invoice is empty. Code written against zero rows cannot be tested, and the
attached-vs-chargeable distinction (app.py ~2550: setup-mode Checkout attaches a card without
making it the invoice default) is exactly the kind of thing to verify against a real customer
rather than assume. The stages exist in the table; this fills them when there is a card.

IDEMPOTENT BY DELETE+INSERT of the window it loaded, per App_Env. Re-running cannot duplicate.
Deliberately not a MERGE: the source is a log, so the window is the authority, and a row that has
left the window should leave here too.

==> NO REGEX IN THE KQL. <== A verbatim KQL string (@"...") treats backslash literally, so a
character class containing \\s is a parse error and the API answers with a bare 400 and a column
number. All cleaning happens in _clean(), which is testable without a round trip.
"""
import argparse
import json
import os
import struct
import subprocess
import sys
from datetime import datetime, timedelta, timezone

import pyodbc
import requests

WORKSPACE_ID = os.environ.get('LOG_ANALYTICS_WORKSPACE_ID',
                              '3a20ea90-0496-4841-975a-aa438085431b')
WAREHOUSES = {
    'dev':  'emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.datawarehouse.fabric.microsoft.com',
    'prod': 'emeh72n2ntdufpj4q665b2lzx4-eljzajgm5cpe5i64szgon7sej4.datawarehouse.fabric.microsoft.com',
}
CONTAINER_APP = {'dev': 'ca-analytically-dev', 'prod': 'ca-analytically-prod'}
VENDOR_DOMAIN = 'analytically.info'

STAGE_ORDER = {'challenge_sent': 1, 'verified': 2, 'token_accepted': 3,
               'card_attached': 4, 'card_chargeable': 5, 'invoice_paid': 6}


def _ts(v):
    """Log Analytics returns e.g. 2026-10-02T11:54:33.1234567Z -- SEVEN fractional digits and a Z,
    which datetime.fromisoformat rejects on older Pythons. Truncate to microseconds and drop the Z
    rather than hand pyodbc a string and hope the driver guesses the same way."""
    if v is None:
        return None
    if isinstance(v, datetime):
        return v.replace(tzinfo=None)
    t = str(v).strip().rstrip('Z')
    if '.' in t:
        head, frac = t.split('.', 1)
        t = head + '.' + frac[:6]
    try:
        return datetime.fromisoformat(t).replace(tzinfo=None)
    except ValueError:
        return None


def _clean(v):
    """Strip whitespace and the quote characters %r formatting leaves behind. None stays None."""
    if v is None:
        return None
    return v.strip().strip('"').strip("'").strip() or None


# ── auth ──────────────────────────────────────────────────────────────────────
# ==> TWO PATHS, BECAUSE THIS RUNS IN TWO PLACES. <== Scheduled as caj-sales-monitor-<env> there
# is no az CLI and no signed-in user, so it must use the app's own service principal exactly as
# appdb_sync.py does. Run by hand from a workstation there is no client secret, so it falls back to
# the delegated az token. The SP path is tried first so the scheduled behaviour is the one that
# gets exercised, rather than only ever being proven in a place it will never run.
_msal_app = None


def _sp_token(resource):
    """Entra token as the app's service principal. None when not configured for it."""
    global _msal_app
    tenant = os.environ.get('TENANT_ID')
    client = os.environ.get('AZURE_CLIENT_ID') or os.environ.get('CLIENT_ID')
    secret = os.environ.get('AZURE_CLIENT_SECRET') or os.environ.get('CLIENT_SECRET')
    if not (tenant and client and secret):
        return None
    import msal
    if _msal_app is None:
        _msal_app = msal.ConfidentialClientApplication(
            client, authority='https://login.microsoftonline.com/%s' % tenant,
            client_credential=secret)
    r = _msal_app.acquire_token_for_client(scopes=[resource.rstrip('/') + '//.default'])
    if 'access_token' not in r:
        raise RuntimeError('token for %s failed: %s'
                           % (resource, r.get('error_description', 'unknown')))
    return r['access_token']


def _az_token(resource):
    """Service principal when configured, else the delegated az CLI token."""
    tok = _sp_token(resource)
    if tok:
        return tok
    return subprocess.check_output(
        ['az', 'account', 'get-access-token', '--resource', resource,
         '--query', 'accessToken', '-o', 'tsv'], shell=True).decode().strip()


def _wh(env):
    tb = _az_token('https://database.windows.net').encode('utf-16-le')
    return pyodbc.connect(
        'Driver={ODBC Driver 18 for SQL Server};Server=%s,1433;Database=WH_Dentally;'
        'Encrypt=yes;TrustServerCertificate=no;' % WAREHOUSES[env],
        attrs_before={1256: struct.pack('<I%ds' % len(tb), len(tb), tb)},
        autocommit=True)      # ==> NOT OPTIONAL: without it every write here rolls back silently.


def _kusto(query, days):
    r = requests.post(
        'https://api.loganalytics.io/v1/workspaces/%s/query' % WORKSPACE_ID,
        headers={'Authorization': 'Bearer ' + _az_token('https://api.loganalytics.io'),
                 'Content-Type': 'application/json'},
        json={'query': query, 'timespan': 'P%dD' % days}, timeout=120)
    if r.status_code >= 400:
        # The API's 400 body carries the line/column of the KQL fault; without printing it the
        # error is just "Bad Request" and unactionable.
        raise SystemExit('Log Analytics %d: %s' % (r.status_code, r.text[:600]))
    t = r.json()['tables'][0]
    cols = [c['name'] for c in t['columns']]
    return [dict(zip(cols, row)) for row in t['rows']]


# ── extract ───────────────────────────────────────────────────────────────────
# ==> extract(), NOT parse(). <== KQL's parse requires the ENTIRE pattern to match, so a line
# from before "tenant=" was added to the log yields NULL for every captured field -- including upn
# -- and the row is silently dropped. Every one of the live practice's 54 accesses is in that older
# format, so a parse-based query reported 3 rows where the truth was 6 days of use. extract() is
# per-field and tolerant: tenant simply comes back empty on the older lines.
# The regexes deliberately contain NO BACKSLASH: a verbatim KQL string treats it literally and the
# query fails to parse, so character classes are written as negated sets instead.
USAGE_KQL = """
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "APPNAME"
| where Log_s has "embed-token issued"
| extend upn    = extract("upn='([^']+)'", 1, Log_s)
| extend report = extract("report=([^ ]+)", 1, Log_s)
| extend tenant = extract("tenant=([^ ]+)", 1, Log_s)
| where isnotempty(upn)
| summarize opens = count(), reports_distinct = dcount(report),
            first_at = min(TimeGenerated), last_at = max(TimeGenerated)
  by upn, tenant, access_date = format_datetime(startofday(TimeGenerated), "yyyy-MM-dd")
"""

FUNNEL_KQL = """
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "APPNAME"
| where Log_s has "funnel "
| extend stage    = extract("funnel ([a-z_]+):", 1, Log_s)
| extend email_h  = extract("email_h=([^ ]+)", 1, Log_s)
| extend domain   = extract("domain=([^ ]+)", 1, Log_s)
| extend practice = extract("practice='([^']*)'", 1, Log_s)
| where isnotempty(stage)
| project event_at = TimeGenerated, stage, email_h, domain, practice
"""


def usage_rows(env, days):
    rows = _kusto(USAGE_KQL.replace('APPNAME', CONTAINER_APP[env]), days)
    out = []
    for r in rows:
        upn = (_clean(r.get('upn')) or '').lower()
        if not upn or '@' not in upn:
            continue   # lines predating the current log format do not always yield a usable upn
        tenant = _clean(r.get('tenant'))
        # "all-permitted" means a staff session scoped to more than one practice: a real session,
        # but not attributable to one tenant, so it is stored with Tenant_ID NULL.
        tenant_id = int(tenant) if (tenant or '').isdigit() else None
        out.append((env, tenant_id, upn[:256],
                    1 if upn.endswith(VENDOR_DOMAIN) else 0,
                    r['access_date'], int(r['opens']), int(r['reports_distinct']),
                    _ts(r.get('first_at')), _ts(r.get('last_at'))))
    return out


def funnel_log_rows(env, days):
    rows = _kusto(FUNNEL_KQL.replace('APPNAME', CONTAINER_APP[env]), days)
    out = []
    for r in rows:
        stage = (_clean(r.get('stage')) or '').rstrip(':')
        if stage not in ('challenge_sent', 'verified', 'token_accepted'):
            continue   # these three come from the app log; invoice_paid comes from Billing
        out.append((env, _ts(r['event_at']), stage, STAGE_ORDER[stage],
                    _clean(r.get('email_h')), _clean(r.get('domain')),
                    _clean(r.get('practice')), None, None))
    return out


def funnel_kv_rows(env):
    """Retired: token_accepted now arrives via the app log, like the other early stages.

    ==> IT USED TO READ THE KEY VAULT PENDING-TRIAL SECRET, AND THAT WAS THE WRONG DOOR. <== Key
    Vault access policies cannot be scoped to one secret, so giving this job's service principal
    `get` would have handed it every secret in the vault -- the Xero and Dentally tokens included --
    to capture a single funnel stage. The app logs the stage instead, at the moment it records the
    pending trial, which costs one line and no new permission. Kept as a no-op so the call site and
    the stage list still read as a complete funnel.
    """
    return []


def funnel_billing_rows(env, cn):
    """invoice_paid, straight from Billing.Stripe_Invoice."""
    cur = cn.cursor()
    cur.execute("""SELECT Tenant_ID, Status, Amount_Pence, Created_At
                   FROM Billing.Stripe_Invoice
                   WHERE Status IS NOT NULL AND LOWER(Status) = 'paid'""")
    return [(env, _ts(r[3]), 'invoice_paid', STAGE_ORDER['invoice_paid'], None, None, None,
             r[0], 'status=%s amount_pence=%s' % (r[1], r[2])) for r in cur.fetchall()]


# ── load ──────────────────────────────────────────────────────────────────────
def load(cn, env, usage, funnel, dry, days):
    if dry:
        print('  DRY RUN -- nothing written')
        return
    cur = cn.cursor()
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    # ==> DELETE ONLY THE WINDOW BEING RELOADED. <== It used to delete every row for the
    # environment, which meant a 30-day run DESTROYED older history: the live practice's six days
    # of use collapsed to three, and once it passed 30 days dormant it would have vanished
    # entirely -- leaving Days_Since_Last_Access NULL and the client reading "never accessed"
    # rather than "dormant", a worse lie than the one this monitor exists to catch. Scoped to the
    # window, the reload stays idempotent AND the warehouse keeps history past Log Analytics'
    # 365-day retention.
    window_start = (datetime.now(timezone.utc) - timedelta(days=days)).date()
    print('  window starts %s -- rows older than that are KEPT' % window_start)

    cur.execute('DELETE FROM Sales.Usage_Daily WHERE App_Env = ? AND Access_Date >= ?',
                env, window_start)
    print('  Usage_Daily    deleted %d, inserting %d' % (cur.rowcount, len(usage)))
    if usage:
        cur.executemany(
            'INSERT INTO Sales.Usage_Daily (App_Env, Tenant_ID, User_UPN, Is_Vendor, Access_Date,'
            ' Report_Opens, Reports_Distinct, First_Access_At, Last_Access_At, DW_Loaded_At)'
            ' VALUES (?,?,?,?,?,?,?,?,?,?)', [tuple(r) + (now,) for r in usage])

    cur.execute('DELETE FROM Sales.Funnel_Event WHERE App_Env = ? AND Event_At >= ?',
                env, window_start)
    print('  Funnel_Event   deleted %d, inserting %d' % (cur.rowcount, len(funnel)))
    if funnel:
        cur.executemany(
            'INSERT INTO Sales.Funnel_Event (App_Env, Event_At, Stage, Stage_Order, Email_Hash,'
            ' Email_Domain, Practice_Name, Tenant_ID, Detail, DW_Loaded_At)'
            ' VALUES (?,?,?,?,?,?,?,?,?,?)', [tuple(r) + (now,) for r in funnel])

    # ==> READ BACK, DO NOT TRUST THE INSERT. <== A silent rollback is the failure mode this file
    # warns about, and rowcount on a Fabric executemany is not confirmation.
    # Read back the WINDOW, not the table: rows older than the window are meant to survive, so a
    # bare count would now fail on a correct load.
    cur.execute('SELECT COUNT(*) FROM Sales.Usage_Daily WHERE App_Env = ? AND Access_Date >= ?',
                env, window_start)
    u = cur.fetchone()[0]
    cur.execute('SELECT COUNT(*) FROM Sales.Funnel_Event WHERE App_Env = ? AND Event_At >= ?',
                env, window_start)
    f = cur.fetchone()[0]
    cur.execute('SELECT COUNT(*) FROM Sales.Usage_Daily WHERE App_Env = ?', env)
    total = cur.fetchone()[0]
    print('  read back      in-window Usage=%d Funnel=%d   (table holds %d usage row(s))'
          % (u, f, total))
    if u != len(usage) or f != len(funnel):
        raise SystemExit('LOAD MISMATCH: expected %d/%d in window, found %d/%d'
                         % (len(usage), len(funnel), u, f))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('env', choices=sorted(WAREHOUSES))
    ap.add_argument('--days', type=int, default=30)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    print('sales-monitor [%s]  window %dd  app %s' % (a.env, a.days, CONTAINER_APP[a.env]))
    cn = _wh(a.env)

    usage = usage_rows(a.env, a.days)
    funnel = (funnel_log_rows(a.env, a.days) + funnel_kv_rows(a.env)
              + funnel_billing_rows(a.env, cn))

    print('  extracted      usage=%d rows  funnel=%d rows' % (len(usage), len(funnel)))
    practice = [r for r in usage if r[3] == 0]
    print('  usage by PRACTICE users (not us): %d of %d row(s)' % (len(practice), len(usage)))
    load(cn, a.env, usage, funnel, a.dry_run, a.days)
    cn.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
