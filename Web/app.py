from flask import Flask, jsonify, send_from_directory, request, g, has_request_context, redirect
from flask_cors import CORS
import msal
import requests
import pyodbc
import struct
import os
import uuid
import logging
import base64
import hmac
import hashlib
import json
import time
import secrets
from datetime import datetime, timedelta
from urllib.parse import urlencode, quote
from dotenv import load_dotenv
import jwt
from jwt import PyJWKClient

load_dotenv()


class _RequestIdFilter(logging.Filter):
    """Inject the current request's correlation id into every log record (or '-')."""
    def filter(self, record):
        try:
            record.request_id = getattr(g, 'request_id', '-') if has_request_context() else '-'
        except Exception:
            record.request_id = '-'
        return True


logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(name)s [%(request_id)s] %(message)s',
)
for _h in logging.getLogger().handlers:
    _h.addFilter(_RequestIdFilter())

app = Flask(__name__, static_folder='.', static_url_path='')
# Restrict CORS to the app's own origins (UI + API are same-origin, so this
# can't affect normal use; it just stops arbitrary sites making cross-origin
# calls). Override with ALLOWED_ORIGINS (comma-separated) if needed.
_allowed_origins = [o.strip() for o in os.environ.get(
    'ALLOWED_ORIGINS',
    'https://app.analytically.info,https://dev.analytically.info,http://localhost:5000,http://localhost:8000'
).split(',') if o.strip()]
CORS(app, origins=_allowed_origins)


@app.before_request
def _assign_request_id():
    # Honour an inbound correlation id if present, else mint one. Used in logs +
    # echoed back in the response so a client error can be traced to server logs.
    g.request_id = request.headers.get('X-Request-ID') or uuid.uuid4().hex[:12]


@app.after_request
def _attach_request_id(response):
    rid = getattr(g, 'request_id', None)
    if rid:
        response.headers['X-Request-ID'] = rid
    return response


@app.after_request
def _security_headers(response):
    # Baseline hardening headers for the authenticated app. The app itself must
    # never be framed (clickjacking a signed-in session); it embeds Power BI in an
    # iframe, but that is us framing PBI, not the reverse, so DENY is safe here.
    response.headers.setdefault('X-Frame-Options', 'DENY')
    response.headers.setdefault('X-Content-Type-Options', 'nosniff')
    response.headers.setdefault('Referrer-Policy', 'strict-origin-when-cross-origin')
    response.headers.setdefault('Strict-Transport-Security', 'max-age=31536000; includeSubDomains')
    # Content-Security-Policy. The allowlist is scoped to exactly what the app loads:
    #   - script/style: same-origin files + the inline <script>/<style> in index.html
    #   - connect: our /api + AAD token endpoints + PBI REST hosts
    #   - frame-src: the PBI report iframe, and AAD's hidden-iframe silent-token flow
    #   - frame-ancestors 'none': mirrors X-Frame-Options DENY (nobody may frame us)
    # Set CSP_MODE=report to ship it as report-only (observe violations without
    # blocking); anything else / unset enforces it.
    _csp = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline'; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; "
        "font-src 'self'; "
        "connect-src 'self' https://login.microsoftonline.com https://*.powerbi.com https://api.powerbi.com; "
        # 'self' is required for MSAL acquireTokenSilent: it uses a hidden iframe that
        # redirects login.microsoftonline.com back to our OWN origin to return the token.
        # Without 'self' that redirect is blocked and returning sessions hang at
        # "Verifying access...". frame-ancestors 'none' still stops OTHERS framing us.
        "frame-src 'self' https://app.powerbi.com https://*.powerbi.com https://login.microsoftonline.com; "
        "frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
    )
    _csp_header = ('Content-Security-Policy-Report-Only'
                  if os.environ.get('CSP_MODE', '').lower() == 'report'
                  else 'Content-Security-Policy')
    response.headers.setdefault(_csp_header, _csp)
    return response

# Defaults to 'dev' so an unconfigured environment FAILS SAFE: APP_ENV gates whether real customer
# email is sent (monitor nudges) and whether _send_email redirects everything to MAIL_REDIRECT, so a
# missing value must mean "not prod". It used to default to 'prod', which meant dev was safe only
# while its APP_ENV variable survived -- drop that one variable and dev would have started emailing
# real practices, since dev carries prod's Graph config and a copy of a live practice's addresses.
# Prod now sets APP_ENV=prod explicitly on the container app rather than relying on the default.
APP_ENV        = os.environ.get('APP_ENV', 'dev')
TENANT_ID      = os.environ['TENANT_ID']
CLIENT_ID      = os.environ['CLIENT_ID']
CLIENT_SECRET  = os.environ['CLIENT_SECRET']
WORKSPACE_ID   = os.environ['WORKSPACE_ID']
DATASET_ID     = os.environ['DATASET_ID']
AZURE_CLIENT_ID     = os.environ.get('AZURE_CLIENT_ID', CLIENT_ID)
AZURE_CLIENT_SECRET = os.environ.get('AZURE_CLIENT_SECRET', CLIENT_SECRET)
# RLS role(s) applied to EVERY embed token. Defaults to 'RLS' so it is never
# silently empty; if it is ever explicitly emptied, /api/embed-token fails closed
# (refuses to mint a token) rather than handing out an unfiltered, all-tenant one.
REPORT_ROLES   = [r.strip() for r in os.environ.get('REPORT_ROLES', 'RLS').split(',') if r.strip()]
FABRIC_SERVER  = os.environ['FABRIC_SERVER']
FABRIC_DB      = os.environ.get('FABRIC_DB', 'WH_Dentally')
# AppDB: the Fabric SQL Database holding the owner-curated target Inputs (Practitioner_Role /
# Targets / Metric_Variance). The Settings screens read/write here (fast OLTP); the warehouse syncs
# from it. See AppDB/README.md. Same SP token as the warehouse (needs a user grant in AppDB).
APPDB_SERVER   = os.environ.get('APPDB_SERVER', '')
APPDB_DB       = os.environ.get('APPDB_DB', '')

PBI_AUTHORITY = f'https://login.microsoftonline.com/{TENANT_ID}'
PBI_SCOPE     = ['https://analysis.windows.net/powerbi/api/.default']
PBI_BASE      = 'https://api.powerbi.com/v1.0/myorg'

REPORTS = {
    'home':       os.environ.get('REPORT_ID_HOME',      ''),
    'revenue':    os.environ.get('REPORT_ID_REVENUE',   ''),
    'patient':    os.environ.get('REPORT_ID_PATIENT',   ''),
    'scheduling': os.environ.get('REPORT_ID_SCHEDULE',  ''),
    'clinical':   os.environ.get('REPORT_ID_CLINICAL',  ''),
    'nhs':        os.environ.get('REPORT_ID_NHS',       ''),
    'finance':    os.environ.get('REPORT_ID_FINANCE',   ''),
    'my_data':    os.environ.get('REPORT_ID_MY_DATA',   ''),
    'day_book':   os.environ.get('REPORT_ID_DAY_BOOK',  ''),
}
app.logger.info("Reports loaded: %s", {k: (v[:8] + '...') if v else '(missing)' for k, v in REPORTS.items()})


# ── Azure AD token validation ─────────────────────────────────────────────────

_jwks_client = PyJWKClient(
    'https://login.microsoftonline.com/common/discovery/v2.0/keys',
)

def _validate_id_token(token):
    signing_key = _jwks_client.get_signing_key_from_jwt(token)
    return jwt.decode(
        token, signing_key.key, algorithms=['RS256'], audience=CLIENT_ID,
        options={'verify_iss': False},
    )

def _auth():
    """Validate Bearer ID token. Returns (upn, None) or (None, error_response)."""
    header = request.headers.get('Authorization', '')
    if not header.startswith('Bearer '):
        return None, (jsonify({'error': 'Authentication required'}), 401)
    try:
        claims = _validate_id_token(header[7:])
        upn = (claims.get('preferred_username') or claims.get('upn') or claims.get('email', '')).lower()
        if not upn:
            return None, (jsonify({'error': 'Authentication required'}), 401)
        return upn, None
    except jwt.ExpiredSignatureError:
        return None, (jsonify({'error': 'Token expired'}), 401)
    except Exception:
        return None, (jsonify({'error': 'Authentication required'}), 401)


def _server_error(e, context):
    """Log full detail server-side; return a generic message to the client."""
    app.logger.exception("%s failed: %s", context, e)
    return jsonify({'error': 'Internal server error'}), 500

# ── Service-principal helpers (PBI + Fabric) ──────────────────────────────────

# Reused MSAL apps (lazy singletons): ConfidentialClientApplication keeps an
# in-memory token cache, so acquire_token_for_client returns a cached token until
# it nears expiry rather than calling AAD on every request. Built on first use,
# not at import, to avoid an authority/network lookup at startup.
_pbi_msal = None
_fabric_msal = None


def _pbi_token():
    global _pbi_msal
    if _pbi_msal is None:
        _pbi_msal = msal.ConfidentialClientApplication(
            CLIENT_ID, authority=PBI_AUTHORITY, client_credential=CLIENT_SECRET,
        )
    result = _pbi_msal.acquire_token_for_client(scopes=PBI_SCOPE)
    if 'access_token' not in result:
        raise RuntimeError(result.get('error_description', 'MSAL token acquisition failed'))
    return result['access_token']


def _fabric_access_token():
    global _fabric_msal
    if _fabric_msal is None:
        _fabric_msal = msal.ConfidentialClientApplication(
            AZURE_CLIENT_ID,
            authority=f'https://login.microsoftonline.com/{TENANT_ID}',
            client_credential=AZURE_CLIENT_SECRET,
        )
    result = _fabric_msal.acquire_token_for_client(scopes=['https://database.windows.net//.default'])
    if 'access_token' not in result:
        raise RuntimeError(result.get('error_description', 'Fabric token acquisition failed'))
    return result['access_token']

def _fabric_conn(autocommit=False):
    token       = _fabric_access_token()
    token_bytes = token.encode('utf-16-le')
    token_struct = struct.pack(f'<I{len(token_bytes)}s', len(token_bytes), token_bytes)
    conn_str = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={FABRIC_SERVER},1433;"
        f"Database={FABRIC_DB};"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )
    return pyodbc.connect(conn_str, attrs_before={1256: token_struct}, autocommit=autocommit)

def _appdb_conn(autocommit=False):
    """Connection to the AppDB Fabric SQL Database (target-model Input tables). Same SP token as the
    warehouse; the SP/managed identity must be granted a user in AppDB (see AppDB/README.md).
    The AppDB (Fabric SQL DB) can PAUSE when idle -- the first connection triggers a resume that may
    time out -- so use a longer connect timeout and retry a couple of times to ride out the wake-up
    rather than instantly 500ing the request."""
    conn_str = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={APPDB_SERVER},1433;"
        f"Database={APPDB_DB};"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
        f"Connection Timeout=30;"
    )
    last = None
    for attempt in range(3):
        token_bytes  = _fabric_access_token().encode('utf-16-le')
        token_struct = struct.pack(f'<I{len(token_bytes)}s', len(token_bytes), token_bytes)
        try:
            return pyodbc.connect(conn_str, attrs_before={1256: token_struct}, autocommit=autocommit)
        except pyodbc.Error as e:
            last = e
            if attempt < 2:
                time.sleep(5)
    raise last

# Is the Fabric capacity up? When it's PAUSED (to save cost pre-revenue) the warehouse is
# unreachable and PBI embeds fail, so we show a holding page rather than a broken app. Cached
# 30s so we don't ping the warehouse on every hit; a short login timeout keeps a paused check fast.
_cap_check = {'ts': 0.0, 'ok': True}
def _capacity_available():
    import time
    now = time.time()
    if now - _cap_check['ts'] < 30:
        return _cap_check['ok']
    ok = False
    try:
        token = _fabric_access_token()
        tb = token.encode('utf-16-le')
        ts = struct.pack(f'<I{len(tb)}s', len(tb), tb)
        cs = (f"Driver={{ODBC Driver 18 for SQL Server}};Server={FABRIC_SERVER},1433;"
              f"Database={FABRIC_DB};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=4;")
        c = pyodbc.connect(cs, attrs_before={1256: ts})
        c.close()
        ok = True
    except Exception:
        ok = False
    _cap_check['ts'] = now
    _cap_check['ok'] = ok
    return ok

# ── Public routes ─────────────────────────────────────────────────────────────

@app.route('/')
def index():
    # Cost-saving pause: when the Fabric capacity is suspended the warehouse + embeds are
    # unreachable, so serve a friendly holding page instead of a broken app.
    if not _capacity_available():
        return send_from_directory('.', 'holding.html')
    return send_from_directory('.', 'index.html')


@app.route('/api/auth-config')
def auth_config():
    """Returns MSAL config needed by the frontend — no auth required."""
    return jsonify({'client_id': CLIENT_ID, 'tenant_id': TENANT_ID})


@app.route('/health')
def health():
    """Liveness/readiness probe for Container Apps — unauthenticated, no external
    deps. Reaching here means the process is up and required config loaded at
    import (the app would have failed to boot otherwise)."""
    return jsonify({'status': 'ok'}), 200

# ── Protected routes ──────────────────────────────────────────────────────────

@app.route('/api/embed-token')
def embed_token():
    upn, err = _auth()
    if err:
        return err

    report_name = request.args.get('report', 'revenue')
    report_id   = REPORTS.get(report_name)
    if not report_id:
        return jsonify({'error': f"Report '{report_name}' not configured"}), 404

    # ── Fail closed: never issue an embed token without RLS row-scoping ───────────
    # 1. The RLS role must be configured. If not, refuse -- do NOT fall back to an
    #    unfiltered token that would expose every tenant's data.
    if not REPORT_ROLES:
        app.logger.warning("embed-token REFUSED: REPORT_ROLES is empty")
        return jsonify({'error': 'Server RLS misconfiguration'}), 500
    # 2. The caller must be a provisioned application user mapped to >= 1 tenant.
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        access, _ = _get_user_access(cur, upn)
        conn.close()
    except Exception:
        return jsonify({'error': 'Authorization check failed'}), 500
    if client_id is None or not tids:
        return jsonify({'error': 'Forbidden'}), 403
    # 3. Enforce the per-module subscription: refuse to mint a token for a report
    #    the user isn't granted, so a hidden menu can't be bypassed via the API.
    if not access.get(report_name, False):
        app.logger.info("embed-token DENIED (module not enabled): upn=%r report=%s", upn, report_name)
        return jsonify({'error': 'Forbidden'}), 403

    try:
        token   = _pbi_token()
        headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

        r = requests.get(
            f'{PBI_BASE}/groups/{WORKSPACE_ID}/reports/{report_id}',
            headers=headers, timeout=10,
        )
        r.raise_for_status()
        report_meta = r.json()
        embed_url   = report_meta['embedUrl']
        dataset_id  = report_meta['datasetId']

        # The RLS effective identity is ALWAYS attached -- row filtering is mandatory.
        identity = {
            'username': upn,
            'roles':    REPORT_ROLES,
            'datasets': [dataset_id],
        }
        # ==> AND IT MUST NAME THE PRACTICE, NOT JUST THE PERSON. <== RLS resolves the UPN to
        # the set of tenants that user may see. That was the whole answer while every user
        # could see exactly one -- but a support login on the Analytically client sees every
        # practice, and a report given the whole set ADDS THEM UP. Two practices' revenue
        # under one practice's name is the single worst thing this product could display.
        #
        # Site cannot do this job. 18 of the 42 active metrics have Supports_Site = 0, so a
        # site slicer leaves those showing the combined total no matter what is selected --
        # which is exactly how this was found.
        #
        # customData carries the practice actually in scope, and the model narrows to it. Set
        # only when the scope is UNAMBIGUOUS: one tenant means one practice. A staff login
        # that has not picked one keeps the full permitted set, which is the deliberate
        # "everything I can see" view rather than an accident.
        #
        # It is an assertion of scope, never of permission. tids is what _get_user_info
        # already resolved from the junction, so the token cannot name a practice the caller
        # is not entitled to -- and the RLS rule keeps the set-membership test alongside this,
        # so the model proves it again rather than trusting the token.
        if len(tids) == 1:
            identity['customData'] = str(tids[0])
        token_body = {'accessLevel': 'View', 'identities': [identity]}
        app.logger.info("embed-token issued: upn=%r roles=%r report=%s tenant=%s",
                        upn, REPORT_ROLES, report_name,
                        identity.get('customData') or 'all-permitted')
        r2 = requests.post(
            f'{PBI_BASE}/groups/{WORKSPACE_ID}/reports/{report_id}/GenerateToken',
            headers=headers, json=token_body, timeout=10,
        )
        r2.raise_for_status()
        _tok = r2.json()
        return jsonify({'token': _tok['token'], 'embedUrl': embed_url, 'reportId': report_id,
                        'expiration': _tok.get('expiration')})

    except requests.HTTPError as e:
        app.logger.exception("embed-token upstream PBI error: %s | %s", e, getattr(e.response, 'text', ''))
        return jsonify({'error': 'Upstream service error'}), 502
    except Exception as e:
        return _server_error(e, 'embed-token')


@app.route('/api/me')
def me():
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        display_name, client_id, tids, maintain_targets = _get_user_info(cur, upn)
        if client_id is None:
            conn.close()
            return jsonify({'error': 'Forbidden'}), 403
        practice_name = None
        if tids:
            placeholders = ','.join(['?'] * len(tids))
            cur.execute(
                f"SELECT TOP 1 Practice_Name FROM Gold.Dim_Practice_Sites WHERE Tenant_ID IN ({placeholders})",
                tids,
            )
            prow = cur.fetchone()
            practice_name = prow[0] if prow else None
        access, practitioner_name = _get_user_access(cur, upn)
        # Trial state for the app banner, from Billing.Account_Billing.Paid_From (billing start = trial end).
        # Paid_From far future (>=2100) = free-forever (no banner); else days-left / expired.
        trial = None
        if tids:
            cur.execute(f"SELECT MIN(Paid_From) FROM Billing.Account_Billing WHERE Tenant_ID IN ({placeholders})", tids)
            prow2 = cur.fetchone()
            pf = prow2[0] if prow2 else None
            if pf is not None:
                if getattr(pf, 'year', 0) >= 2100:
                    trial = {'status': 'free_forever'}
                else:
                    days = (pf - datetime.utcnow().date()).days
                    trial = {'status': 'active' if days > 0 else 'expired',
                             'days_left': days, 'paid_from': pf.isoformat()}
        # The practice picker, for our own logins only. Sent with /api/me so the picker is populated
        # in the same round trip that establishes who you are -- there is no moment where the app
        # knows it is staff but not yet which practices exist.
        practices = []
        if _is_staff(upn):
            # ==> BUILT FROM ACCESS, NOT OWNERSHIP. <== This grouped Audit.Tenants by
            # Client_ID, so it could only ever list clients that OWN a tenant. The
            # Analytically client owns none and sees them all, so it was missing from its own
            # picker: no way to select it, and no way back to it once another practice had
            # been picked. The name came from Dim_Practice_Sites too, which is a practice's
            # name rather than the client's -- fine while they were one and the same.
            cur.execute(
                "SELECT c.Client_ID, c.Client_Name, COUNT(DISTINCT a.Tenant_ID) "
                "FROM Security.Clients c "
                "JOIN Security.Client_Tenant_Access a ON a.Client_ID = c.Client_ID "
                "JOIN Audit.Tenants t ON t.Tenant_ID = a.Tenant_ID "
                "WHERE ISNULL(t.Is_Active, 1) = 1 "
                "GROUP BY c.Client_ID, c.Client_Name ORDER BY c.Client_Name")
            practices = [{'client_id': r[0], 'name': r[1] or r[0], 'tenants': r[2]}
                         for r in cur.fetchall()]
        conn.close()
        return jsonify({
            'display_name':         display_name or upn,
            'client_id':            client_id,
            'tenant_ids':           tids,
            'practice_name':        practice_name,
            'maintain_targets':     maintain_targets,
            'access':               access,
            'practitioner_full_name': practitioner_name,
            'env':                  APP_ENV,
            'trial':                trial,
            'is_staff':             _is_staff(upn),
            'practices':            practices,
        })
    except Exception as e:
        return _server_error(e, 'me')


@app.route('/api/definitions')
def definitions():
    """Plain-English metric glossary for the in-product help panel.
    Grouped client-side by Section; the Home tab shows every section."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, _, _ = _get_user_info(cur, upn)
        if client_id is None:
            conn.close()
            return jsonify({'error': 'Forbidden'}), 403

        cur.execute(
            "SELECT Metric_Key, Display_Name, Section, Format_Type, "
            "Description, Long_Description "
            "FROM Config.Metric_Definitions WHERE Is_Active = 1 ORDER BY Display_Order"
        )
        metrics = [
            {'key': r[0], 'display_name': r[1], 'section': r[2],
             'format_type': r[3], 'description': r[4],
             'long_description': r[5] or r[4]}
            for r in cur.fetchall()
        ]
        conn.close()
        return jsonify({'metrics': metrics})
    except Exception as e:
        return _server_error(e, 'definitions')


@app.route('/api/filters')
def filters():
    upn, err = _auth()
    if err:
        return err

    active_only = request.args.get('active_only', '1') == '1'
    role_filter = request.args.get('role', 'all')
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        if client_id is None:
            conn.close()
            return jsonify({'error': 'Forbidden'}), 403

        placeholders = ','.join(['?'] * len(tids)) if tids else 'NULL'
        cur.execute(
            f"SELECT Site_ID, Site_Name "
            f"FROM   Gold.Dim_Practice_Sites "
            f"WHERE  Tenant_ID IN ({placeholders}) AND Site_Active = 1 "
            f"ORDER BY Site_Name",
            tids,
        )
        sites = [{'id': str(r[0]), 'name': r[1]} for r in cur.fetchall()]

        active_clause = "AND Active = 1 " if active_only else ""
        # Non-clinical roles are never "practitioners" -- exclude always (even when showing inactive).
        excl_clause   = "AND LOWER(ISNULL(Role,'')) NOT IN ('administrator','receptionist','practice manager') "
        role_clause   = "AND LOWER(Custom_Role) = LOWER(?) " if role_filter != 'all' else ""
        pract_params  = list(tids) + ([role_filter] if role_filter != 'all' else [])
        cur.execute(
            f"SELECT MIN(Practitioner_ID) AS Practitioner_ID, Full_Name "
            f"FROM   Gold.Dim_Practitioners "
            f"WHERE  Tenant_ID IN ({placeholders}) "
            f"AND    pk_Practitioner > 0 "
            f"{active_clause}"
            f"{excl_clause}"
            f"{role_clause}"
            f"GROUP BY Full_Name "     # dedup by name (same person can have >1 record)
            f"ORDER BY Full_Name",
            pract_params,
        )
        practitioners = [{'id': str(r[0]), 'name': r[1]} for r in cur.fetchall()]

        # Role dropdown options = the curated Custom_Role values actually in use by clinical
        # practitioners. This is the SAME column the practitioner filter and the embedded report
        # now key off, so the dropdown, the practitioner list and the report always agree.
        cur.execute(
            f"SELECT DISTINCT Custom_Role "
            f"FROM   Gold.Dim_Practitioners "
            f"WHERE  Tenant_ID IN ({placeholders}) AND pk_Practitioner > 0 AND Active = 1 "
            f"{excl_clause}"
            f"AND    NULLIF(LTRIM(RTRIM(Custom_Role)), '') IS NOT NULL "
            f"ORDER BY Custom_Role",
            tids,
        )
        roles = [r[0] for r in cur.fetchall()]
        # Period options = the tenant's date groupings (Last 3 Months, Last 12 Months, then the practice
        # FYs cutover..current). Per-tenant + FYyy labels -> driven by the warehouse, not hardcoded.
        # Resilient: a warehouse not yet on the tenant-FY grouping (no Tenant_ID column) must NOT break
        # the whole filter payload -> fall back to [] and the app keeps its static period options.
        periods = []
        try:
            cur.execute(f"SELECT DISTINCT Date_Grouping FROM Gold.Dim_Date_Grouping WHERE Tenant_ID IN ({placeholders})", tids)
            _pv = [r[0] for r in cur.fetchall()]
            def _prank(v):
                if v == 'Last 3 Months':  return (0, 0)
                if v == 'Last 12 Months': return (1, 0)
                yy = (v or '')[2:]                      # 'FY26' -> '26'; FYyy newest first
                return (2, -(int(yy) if yy.isdigit() else 0))
            periods = sorted(_pv, key=_prank)
        except Exception:
            periods = []
        conn.close()
        return jsonify({'sites': sites, 'practitioners': practitioners, 'roles': roles, 'periods': periods})

    except Exception as e:
        # Preserve the 200 + empty-lists client contract; log detail server-side.
        app.logger.exception("filters failed: %s", e)
        return jsonify({'sites': [], 'practitioners': [], 'roles': []})


# ── Connect Xero (self-serve OAuth onboarding) ───────────────────────────────
# A tenant admin connects their practice's Xero from inside the app: the browser is
# redirected to Xero's consent (their own browser, Xero's domain), and the callback
# writes the token to Key Vault + auto-maps the org to THIS tenant (derived from the
# signed-in user), so there is no manual token/GUID handling. Isolated per env via
# xero-tokens-<env> / xero-org-map-<env>. See XERO_ONBOARDING.md / project memory.

XERO_ENV          = APP_ENV if APP_ENV in ('dev', 'prod') else 'prod'
XERO_KEYVAULT_URL = os.environ.get('XERO_KEYVAULT_URL', 'https://kv-analytically.vault.azure.net/')
XERO_AUTHORIZE    = 'https://login.xero.com/identity/connect/authorize'
XERO_TOKEN_URL    = 'https://identity.xero.com/connect/token'
XERO_CONNECTIONS  = 'https://api.xero.com/connections'
# Standard granular document scopes (NOT the gated accounting.journals.read).
XERO_SCOPES = (
    'openid profile email accounting.settings.read accounting.invoices.read '
    'accounting.banktransactions.read accounting.manualjournals.read '
    'accounting.payments.read accounting.reports.profitandloss.read offline_access'
)

_kv_client_singleton = None
_xero_app_creds = {}


def _kv():
    global _kv_client_singleton
    if _kv_client_singleton is None:
        from azure.identity import DefaultAzureCredential
        from azure.keyvault.secrets import SecretClient
        _kv_client_singleton = SecretClient(
            vault_url=XERO_KEYVAULT_URL, credential=DefaultAzureCredential())
    return _kv_client_singleton


def _kv_get(name, default=None):
    try:
        return _kv().get_secret(name).value
    except Exception:
        return default


def _kv_set(name, value):
    _kv().set_secret(name, value)


def _kv_json(name):
    """Read a JSON secret, tolerating a leading UTF-8 BOM / whitespace (secrets set via
    some tooling get a BOM the SDK returns raw). Empty/missing -> {}."""
    v = (_kv_get(name) or '').lstrip('﻿').strip()
    try:
        return json.loads(v) if v else {}
    except Exception:
        return {}


def _xero_client():
    """Xero app id/secret from Key Vault (shared across envs), cached in-process."""
    if not _xero_app_creds:
        _xero_app_creds['id']     = _kv_get('xero-client-id')
        _xero_app_creds['secret'] = _kv_get('xero-client-secret')
    return _xero_app_creds['id'], _xero_app_creds['secret']


def _state_key():
    # HMAC key for the OAuth `state` (CSRF + carries the tenant). Reuse the app SP
    # secret (high-entropy, already present) unless XERO_STATE_SECRET is set.
    return (os.environ.get('XERO_STATE_SECRET') or CLIENT_SECRET).encode()


def _sign_state(payload):
    raw = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode()
    sig = hmac.new(_state_key(), raw.encode(), hashlib.sha256).hexdigest()
    return raw + '.' + sig


def _verify_state(state, max_age=900):
    try:
        raw, sig = state.rsplit('.', 1)
        expected = hmac.new(_state_key(), raw.encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(sig, expected):
            return None
        payload = json.loads(base64.urlsafe_b64decode(raw))
        if time.time() - payload.get('ts', 0) > max_age:
            return None
        return payload
    except Exception:
        return None


def _xero_redirect_uri():
    # Must EXACTLY match a redirect URI registered on the Xero app.
    return f'https://{request.host}/api/xero/callback'


def _primary_site_id(tenant_id):
    try:
        conn = _fabric_conn()
        cur = conn.cursor()
        cur.execute(
            "SELECT TOP 1 Site_ID FROM Gold.Dim_Practice_Sites "
            "WHERE Tenant_ID = ? AND Site_Active = 1 ORDER BY Site_Name", tenant_id)
        row = cur.fetchone()
        conn.close()
        return str(row[0]) if row else None
    except Exception:
        return None


@app.route('/api/xero/status')
def xero_status():
    """Is this tenant's Xero connected, and may this user connect it?"""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        conn.close()
        if client_id is None:
            return jsonify({'error': 'Forbidden'}), 403
        tenant_id = tids[0] if tids else None
        org_map = _kv_json(f'xero-org-map-{XERO_ENV}')
        orgs = [v for v in org_map.values() if v.get('tenant_id') == tenant_id]
        return jsonify({'connected': len(orgs) > 0,
                        'org_count': len(orgs),
                        'can_connect': bool(maintain)})
    except Exception as e:
        return _server_error(e, 'xero-status')


@app.route('/api/xero/connect')
def xero_connect():
    """Start the OAuth flow: return the Xero authorize URL (the UI then navigates to it).
    Admin-only; the signed state carries this user's tenant so the callback can auto-map."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        conn.close()
        if client_id is None:
            return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            return jsonify({'error': 'Only a practice admin can connect Xero'}), 403
        if not tids:
            return jsonify({'error': 'No tenant for this user'}), 400
        cid, _secret = _xero_client()
        if not cid:
            return jsonify({'error': 'Xero app not configured'}), 500
        state = _sign_state({'tenant_id': tids[0], 'upn': upn,
                             'ts': time.time(), 'nonce': uuid.uuid4().hex})
        params = urlencode({
            'response_type': 'code',
            'client_id':     cid,
            'redirect_uri':  _xero_redirect_uri(),
            'scope':         XERO_SCOPES,
            'state':         state,
        }, quote_via=quote)
        return jsonify({'authorize_url': XERO_AUTHORIZE + '?' + params})
    except Exception as e:
        return _server_error(e, 'xero-connect')


@app.route('/api/xero/callback')
def xero_callback():
    """Xero redirects here after consent (browser navigation, no bearer token -- the
    signed state carries the tenant). Exchange the code, discover the org, and persist
    the token + org->tenant map to Key Vault (this env)."""
    if request.args.get('error'):
        app.logger.warning("xero callback error: %s", request.args.get('error'))
        return redirect('/?xero=error')
    code  = request.args.get('code')
    state = _verify_state(request.args.get('state', ''))
    if not code or not state:
        return redirect('/?xero=error')
    tenant_id = state['tenant_id']
    try:
        cid, csecret = _xero_client()
        basic = 'Basic ' + base64.b64encode(f'{cid}:{csecret}'.encode()).decode()
        tr = requests.post(XERO_TOKEN_URL, headers={
            'Authorization': basic,
            'Content-Type':  'application/x-www-form-urlencoded',
        }, data={
            'grant_type':   'authorization_code',
            'code':         code,
            'redirect_uri': _xero_redirect_uri(),
        }, timeout=30)
        tr.raise_for_status()
        tokens = tr.json()

        cr = requests.get(XERO_CONNECTIONS, headers={
            'Authorization': 'Bearer ' + tokens['access_token'],
            'Content-Type':  'application/json',
        }, timeout=30)
        cr.raise_for_status()
        tenants = [{'tenantId': c['tenantId'], 'tenantName': c.get('tenantName')}
                   for c in cr.json()]
        if not tenants:
            return redirect('/?xero=error')

        # Persist token (keyed per Dentally tenant so re-connecting updates in place).
        tok_secret = f'xero-tokens-{XERO_ENV}'
        all_tokens = _kv_json(tok_secret)
        all_tokens[f't{tenant_id}'] = {'tokens': tokens, 'tenants': tenants}
        _kv_set(tok_secret, json.dumps(all_tokens))

        # Auto-map every connected org -> this tenant + its primary site.
        default_site = _primary_site_id(tenant_id)
        map_secret = f'xero-org-map-{XERO_ENV}'
        org_map = _kv_json(map_secret)
        for t in tenants:
            org_map[t['tenantId']] = {'tenant_id': tenant_id, 'default_site_id': default_site}
        _kv_set(map_secret, json.dumps(org_map))

        app.logger.info("xero connected: tenant=%s orgs=%s", tenant_id,
                        [t['tenantName'] for t in tenants])
        return redirect('/?xero=connected')
    except Exception as e:
        app.logger.exception("xero callback failed: %s", e)
        return redirect('/?xero=error')


# ── Guided onboarding: public 30-day trial (pre-account, OUTSIDE the app) ──────
# A NEW practice has no app login yet, so onboarding is PUBLIC (no _auth) and lives outside the
# authed app: the marketing site's "Get started" links to /onboarding (served here). Flow:
#   1. principal enters practice name + their work email  ->  we email a 6-digit code (challenge)
#   2. they enter the code (response)  ->  email verified; that address is taken as the PRINCIPAL
#   3. they attest they have appropriate Dentally access + the authority to share the data
#   4. Connect Dentally (OAuth, on Dentally's domain)  ->  callback captures the token
#   5. we record a PENDING TRIAL (token + details + Paid_From = +TRIAL_DAYS) for the evening run
# Auto-provision needs no human step because completing OAuth requires a real Dentally token; the
# email challenge + attestation cover authenticity + authority. STATELESS: each step hands the next a
# short-lived HMAC-signed token (no server session store).
#
# CONFIRM/CONFIGURE: Dentally partner-app creds (KV dentally-client-id / dentally-client-secret) +
# redirect URI https://<host>/api/onboarding/dentally/callback; an email provider (see _send_email).
# All overridable via env so nothing is hard-coded to a guess.
DENTALLY_ENV       = APP_ENV if APP_ENV in ('dev', 'prod') else 'prod'
DENTALLY_AUTHORIZE = os.environ.get('DENTALLY_AUTHORIZE', 'https://api.dentally.co/oauth/authorize')
DENTALLY_TOKEN_URL = os.environ.get('DENTALLY_TOKEN_URL', 'https://api.dentally.co/oauth/token')
DENTALLY_API_BASE  = os.environ.get('DENTALLY_API_BASE',  'https://api.dentally.co/v1')
DENTALLY_UA        = os.environ.get('DENTALLY_USER_AGENT', 'Analytically/1.0 (onboarding)')  # Dentally 403s without a User-Agent
DENTALLY_SCOPES    = os.environ.get('DENTALLY_SCOPES',
    'user:read patient:read appointment:read practitioner:read site:read '
    'treatment:read payment_plan:read contract:read invoice:read')  # confirm the exact set with Dentally
TRIAL_DAYS         = int(os.environ.get('ONBOARDING_TRIAL_DAYS', '30'))
# Where to send the "an onboarding is waiting to be provisioned" alert. Onboarding is throttled/run
# by hand, so the operator needs a nudge per new signup. Defaults to the app's reply-to address.
ONBOARDING_NOTIFY  = os.environ.get('ONBOARDING_NOTIFY', os.environ.get('ONBOARDING_REPLY_TO', 'sales@analytically.info'))
# Every Dentally endpoint the ingest reads, grouped by the read-permission a practice ticks when
# creating the personal access token. The onboarding preflight probes each with the pasted token so
# we confirm -- in real time -- that all the tables we need are actually readable BEFORE accepting the
# signup. Keep this in step with the ENDPOINTS list in Fabric/Notebooks/Ingest_Dentally.ipynb.
DENTALLY_REQUIRED = [
    ('user:read',        ['users']),
    ('practice:read',    ['practice', 'sites', 'practitioners', 'acquisition_sources',
                          'appointment_cancellation_reasons', 'sundries', 'contracts', 'waiting_lists']),
    ('appointment:read', ['appointments', 'treatment_appointments', 'rota_practitioner_diaries']),
    ('patient:read',     ['patients', 'patient_referrals', 'recalls']),
    ('financials:read',  ['invoices', 'invoice_items', 'payments', 'nhs_claims']),
    ('treatments',       ['treatments', 'treatment_categories', 'treatment_plans',
                          'treatment_plan_items', 'payment_plans']),
]
_dentally_app_creds = {}


def _dentally_preflight(token):
    """Probe every Dentally endpoint the ingest reads, with the pasted token, in parallel. Deliberately
    agnostic to Dentally's exact status codes (a missing scope may surface as 401 or 403): a table is
    readable ONLY on a 2xx. Returns (token_valid, groups):
      * token_valid is False only when NOTHING was readable AND at least one probe was explicitly
        rejected (401/403) -- i.e. the token itself is wrong, not just a per-scope gap.
      * per table -- 'ok' (2xx), 'blocked' (401/403: readable-permission not granted / token rejected),
        'unconfirmed' (404/5xx/network: couldn't check -- non-blocking so a path quirk or transient
        error never blocks a real signup; the operator re-checks on the manual run)."""
    import concurrent.futures
    headers = {'Authorization': 'Bearer ' + token, 'User-Agent': DENTALLY_UA}
    paths = [p for _, ps in DENTALLY_REQUIRED for p in ps]

    def _probe(path):
        try:
            r = requests.get(f'{DENTALLY_API_BASE}/{path}', headers=headers,
                             params={'per_page': 1}, timeout=8)
            return path, r.status_code
        except requests.RequestException:
            return path, None

    status = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as ex:
        for path, code in ex.map(_probe, paths):
            status[path] = code

    codes        = list(status.values())
    any_ok       = any(c and 200 <= c < 300 for c in codes)
    any_rejected = any(c in (401, 403) for c in codes)
    token_valid  = any_ok or not any_rejected   # nothing readable + an explicit rejection = bad token

    def _state(c):
        if c and 200 <= c < 300: return 'ok'
        if c in (401, 403):      return 'blocked'
        return 'unconfirmed'

    groups = []
    for scope, ps in DENTALLY_REQUIRED:
        tables = [{'name': p, 'state': _state(status.get(p))} for p in ps]
        # A permission is confirmed granted once ANY of its endpoints reads and NONE is explicitly
        # blocked -- one 2xx proves the scope. Endpoints that need params (e.g. the diary returns 400
        # bare) or are slow (recalls can time out) stay 'unconfirmed' without dragging the group down.
        blocked = any(t['state'] == 'blocked' for t in tables)
        readable = any(t['state'] == 'ok' for t in tables)
        groups.append({'scope': scope, 'ok': readable and not blocked, 'tables': tables})
    return token_valid, groups


def _dentally_client():
    """Dentally partner-app id/secret from Key Vault, cached in-process."""
    if not _dentally_app_creds:
        _dentally_app_creds['id']     = _kv_get('dentally-client-id')
        _dentally_app_creds['secret'] = _kv_get('dentally-client-secret')
    return _dentally_app_creds['id'], _dentally_app_creds['secret']


def _onboarding_redirect_uri():
    # Must EXACTLY match a redirect URI registered on the Dentally app.
    return f'https://{request.host}/api/onboarding/dentally/callback'


def _code_hmac(code, email):
    return hmac.new(_state_key(), f'{email}:{code}'.encode(), hashlib.sha256).hexdigest()


# ── Outgoing mail: Microsoft 365 (Graph) primary, ACS fallback ────────────────
# analytically.info runs on Microsoft 365 (MX -> outlook; SPF -> "include:spf.protection.outlook.com
# -all"), so the aligned + branded way to send is via Graph AS a real mailbox (e.g. support@) rather
# than ACS from the *.azurecomm.net domain. Opt-in with GRAPH_SEND once the app registration has the
# Mail.Send APPLICATION permission (admin-consented) + an Exchange Application Access Policy scopes it
# to GRAPH_FROM. Reuses the app's confidential-client creds. Falls back to ACS on any Graph error.
GRAPH_SEND = os.environ.get('GRAPH_SEND', '').strip().lower() in ('1', 'true', 'yes', 'on')
GRAPH_FROM = os.environ.get('GRAPH_FROM', 'support@analytically.info')
# Every non-prod email is re-addressed here. Dev has the same GRAPH_SEND config as prod, and dev's
# tenant 100 is a copy of a live practice, so this is the only thing standing between a test and a
# real customer's inbox. Overridable, but it must never be blank outside prod.
MAIL_REDIRECT = os.environ.get('MAIL_REDIRECT', 'support@analytically.info')
_graph_msal = None


def _graph_token():
    global _graph_msal
    if _graph_msal is None:
        _graph_msal = msal.ConfidentialClientApplication(
            CLIENT_ID, authority=f'https://login.microsoftonline.com/{TENANT_ID}', client_credential=CLIENT_SECRET)
    result = _graph_msal.acquire_token_for_client(scopes=['https://graph.microsoft.com/.default'])
    if 'access_token' not in result:
        raise RuntimeError(result.get('error_description', 'Graph token acquisition failed'))
    return result['access_token']


def _send_email(to, subject, body, sender=None, reply_to=None):
    """Send a transactional email. Prefers Microsoft 365 via Graph (GRAPH_SEND) -- branded + SPF/DKIM/
    DMARC-aligned, sending AS a real analytically.info mailbox (default GRAPH_FROM). Else Azure
    Communication Services (managed *.azurecomm.net sender), else SMTP; otherwise (dev) logs the body.
    `sender` chooses the Graph mailbox to send as; ACS ignores it (can only send from its own domain).

    NON-PROD REDIRECT: outside prod every message is re-addressed to MAIL_REDIRECT
    (support@analytically.info). Dev carries the same GRAPH_SEND/GRAPH_FROM config as prod, so mail
    from dev really does leave the building -- and dev's tenant 100 is a copy of a live practice,
    so its Application_Users and Billing_Contact hold REAL staff addresses. Without this, testing a
    token nudge, a primary handover or a termination would email an actual dental practice. The
    intended recipient is preserved in the subject and body so the test is still meaningful.
    """
    reply_to = reply_to or os.environ.get('ONBOARDING_REPLY_TO', 'sales@analytically.info')
    if APP_ENV != 'prod':
        intended = to
        to = MAIL_REDIRECT
        subject = f'[{APP_ENV.upper()} -> {intended}] {subject}'
        body = (f"--- {APP_ENV} redirect: this would have been sent to {intended} ---\n\n") + body
        app.logger.warning("mail redirected (%s): %r -> %s", APP_ENV, intended, to)

    # 1) Microsoft 365 via Graph -- the aligned/branded path when enabled.
    if GRAPH_SEND:
        graph_from = sender or GRAPH_FROM
        try:
            r = requests.post(
                f'https://graph.microsoft.com/v1.0/users/{graph_from}/sendMail',
                headers={'Authorization': 'Bearer ' + _graph_token(), 'Content-Type': 'application/json'},
                json={'message': {'subject': subject,
                                  'body': {'contentType': 'Text', 'content': body},
                                  'toRecipients': [{'emailAddress': {'address': to}}],
                                  'replyTo':      [{'emailAddress': {'address': reply_to}}]},
                      'saveToSentItems': True},
                timeout=30)
            r.raise_for_status()
            return True
        except Exception as e:
            app.logger.warning("graph sendMail (%s) failed, falling back to ACS: %s", graph_from, e)

    # 2) Azure Communication Services -- sender must be on a domain connected to the ACS resource, so
    #    ignore any requested sender and use the managed-domain address.
    acs_sender = os.environ.get('ONBOARDING_FROM', 'DoNotReply@analytically.info')
    endpoint = os.environ.get('ACS_ENDPOINT')
    acs_conn = _kv_get('acs-connection-string') or os.environ.get('ACS_CONNECTION_STRING')
    if endpoint or acs_conn:
        from azure.communication.email import EmailClient
        if endpoint:
            from azure.identity import DefaultAzureCredential
            client = EmailClient(endpoint, DefaultAzureCredential())
        else:
            client = EmailClient.from_connection_string(acs_conn)
        client.begin_send({
            'senderAddress': acs_sender,
            'recipients': {'to': [{'address': to}]},
            'replyTo':     [{'address': reply_to}],
            'content':     {'subject': subject, 'plainText': body},
        }).result()
        return True

    # 3) SMTP fallback
    host = os.environ.get('ONBOARDING_SMTP_HOST')
    if host:
        import smtplib
        from email.mime.text import MIMEText
        msg = MIMEText(body)
        msg['Subject'] = subject
        msg['From'] = acs_sender
        msg['To'] = to
        with smtplib.SMTP(host, int(os.environ.get('ONBOARDING_SMTP_PORT', '587'))) as s:
            s.starttls()
            user = os.environ.get('ONBOARDING_SMTP_USER')
            if user:
                s.login(user, os.environ.get('ONBOARDING_SMTP_PASS', ''))
            s.sendmail(msg['From'], [to], msg.as_string())
        return True

    app.logger.warning("email (NO PROVIDER configured) to=%s subject=%s :: %s", to, subject, body)
    return False


def _notify_owner_pending(key, entry):
    """Tell the operator a new onboarding is waiting so the (manual, throttled) provisioning run can be
    scheduled. Best-effort -- a notify failure must never fail the capture (the token is already stored)."""
    try:
        body = (
            "A new practice has completed onboarding and is waiting to be provisioned.\n\n"
            f"Practice:        {entry.get('practice_name') or '(unknown)'}\n"
            f"Principal email: {entry.get('principal_email')}\n"
            f"Dentally id:     {entry.get('dentally_practice_id') or '(not captured)'}\n"
            f"Auth method:     {entry.get('auth_method', 'oauth')}\n"
            f"Trial paid-from: {entry.get('paid_from')}\n"
            f"Captured at:     {entry.get('created_at')}\n"
            f"Store key:       {key}   (Key Vault secret onboarding-pending-{DENTALLY_ENV})\n\n"
            "Throttle and run the onboarding when ready."
        )
        subj = f"Onboarding pending: {entry.get('practice_name') or entry.get('principal_email')}"
        _send_email(ONBOARDING_NOTIFY, subj, body)
    except Exception as e:
        app.logger.warning("owner notify failed (non-fatal): %s", e)


@app.route('/onboarding')
def onboarding_page():
    """Public, unauthenticated onboarding page -- the guided trial dialogue, served outside the app shell."""
    return send_from_directory('.', 'onboarding.html')


@app.route('/pricing')
def pricing_page():
    """Public pricing page (pre-account)."""
    return send_from_directory('.', 'pricing.html')


_pricing_cache = {'ts': 0.0, 'data': None}


@app.route('/api/pricing')
def api_pricing():
    """Public current price list per reporting profile (Admin is a free flag, so not priced separately).
    Cached in-process for 10 minutes so a public page never hammers / cold-starts the warehouse."""
    try:
        if _pricing_cache['data'] is not None and time.time() - _pricing_cache['ts'] < 600:
            return jsonify({'profiles': _pricing_cache['data']})
        conn = _fabric_conn(); cur = conn.cursor()
        cur.execute("SELECT p.Profile_Key, p.Monthly_Price FROM Billing.Profile_Pricing p "
                    "JOIN (SELECT Profile_Key, MAX(Valid_From) vf FROM Billing.Profile_Pricing "
                    "WHERE Valid_From <= CAST(SYSUTCDATETIME() AS DATE) AND (Valid_To IS NULL OR Valid_To >= CAST(SYSUTCDATETIME() AS DATE)) "
                    "GROUP BY Profile_Key) m ON m.Profile_Key = p.Profile_Key AND m.vf = p.Valid_From")
        prices = {r[0]: float(r[1]) for r in cur.fetchall()}
        conn.close()
        data = [{'key': k, 'name': _PROFILES[k]['label'], 'desc': _PROFILES[k].get('desc', ''), 'price': prices.get(k, 0.0)}
                for k in ('full', 'clinician', 'front_office') if k in _PROFILES]
        _pricing_cache.update(ts=time.time(), data=data)
        return jsonify({'profiles': data})
    except Exception as e:
        return _server_error(e, 'pricing')


@app.route('/api/onboarding/challenge', methods=['POST'])
def onboarding_challenge():
    """Step 1: email a 6-digit code to the principal's address. Returns a signed challenge token that
    carries the email + an HMAC of the code (never the code itself) for the stateless verify step."""
    data = request.get_json(silent=True) or {}
    email = (data.get('email') or '').strip().lower()
    practice = (data.get('practice_name') or '').strip()
    if '@' not in email or not practice:
        return jsonify({'error': 'Enter your practice name and a valid work email.'}), 400
    code = f'{secrets.randbelow(1000000):06d}'
    _send_email(email, 'Your Analytically verification code',
                f'Your Analytically verification code is {code}. It expires in 15 minutes.')
    challenge = _sign_state({'t': 'chal', 'email': email, 'practice': practice,
                             'code_h': _code_hmac(code, email), 'ts': time.time()})
    return jsonify({'challenge': challenge, 'sent': True})


@app.route('/api/onboarding/verify', methods=['POST'])
def onboarding_verify():
    """Step 2: check the code against the signed challenge; issue a 'verified principal' token. The
    verified email is taken as the practice PRINCIPAL (its owner/admin account)."""
    data = request.get_json(silent=True) or {}
    payload = _verify_state(data.get('challenge', ''), max_age=900)
    code = (data.get('code') or '').strip()
    if not payload or payload.get('t') != 'chal':
        return jsonify({'error': 'This step expired -- please start again.'}), 400
    if not hmac.compare_digest(payload.get('code_h', ''), _code_hmac(code, payload['email'])):
        return jsonify({'error': 'That code is not right.'}), 400
    verified = _sign_state({'t': 'verified', 'email': payload['email'],
                            'practice': payload['practice'], 'ts': time.time()})
    return jsonify({'verified': verified, 'email': payload['email']})


@app.route('/api/onboarding/dentally/connect')
def onboarding_connect():
    """Step 4: with a verified principal + the authority attestation, return the Dentally authorize URL."""
    payload = _verify_state(request.args.get('verified', ''), max_age=1800)
    if not payload or payload.get('t') != 'verified':
        return jsonify({'error': 'Please verify your email first.'}), 400
    if request.args.get('attested') != '1':
        return jsonify({'error': 'You must confirm you are authorised to share the data.'}), 400
    cid, _secret = _dentally_client()
    if not cid:
        return jsonify({'error': 'Dentally app not configured'}), 500
    state = _sign_state({'t': 'onb', 'email': payload['email'], 'practice': payload['practice'],
                         'attested': True, 'ts': time.time(), 'nonce': uuid.uuid4().hex})
    params = urlencode({
        'response_type': 'code',
        'client_id':     cid,
        'redirect_uri':  _onboarding_redirect_uri(),
        'scope':         DENTALLY_SCOPES,
        'state':         state,
    }, quote_via=quote)
    return jsonify({'authorize_url': DENTALLY_AUTHORIZE + '?' + params})


@app.route('/api/onboarding/dentally/callback')
def onboarding_callback():
    """Step 5: exchange the code, identify the practice, and record a PENDING TRIAL (token + details
    + Paid_From = +TRIAL_DAYS) keyed by the Dentally practice id (idempotent -- a re-connect updates
    in place). The evening onboarding run provisions the tenant + pulls; that step is the next layer."""
    if request.args.get('error'):
        return redirect('/onboarding?status=error')
    code  = request.args.get('code')
    state = _verify_state(request.args.get('state', ''), max_age=1800)
    if not code or not state or state.get('t') != 'onb':
        return redirect('/onboarding?status=error')
    try:
        cid, csecret = _dentally_client()
        tr = requests.post(DENTALLY_TOKEN_URL, headers={
            'User-Agent':   DENTALLY_UA,
            'Content-Type': 'application/x-www-form-urlencoded',
        }, data={
            'grant_type':    'authorization_code',
            'code':          code,
            'redirect_uri':  _onboarding_redirect_uri(),
            'client_id':     cid,
            'client_secret': csecret,
        }, timeout=30)
        tr.raise_for_status()
        tokens = tr.json()

        practice_id, practice_name = None, state.get('practice')
        try:
            pr = requests.get(DENTALLY_API_BASE + '/practice', headers={
                'Authorization': 'Bearer ' + tokens['access_token'],
                'User-Agent':    DENTALLY_UA,
            }, timeout=30)
            if pr.ok:
                body = pr.json()
                practices = body.get('practices') or ([body['practice']] if body.get('practice') else [])
                if practices:
                    practice_id   = practices[0].get('id')
                    practice_name = practices[0].get('name') or practice_name
        except Exception:
            pass

        # Idempotent per Dentally practice; keep the full OAuth set + the trial's Paid_From.
        key = f'dentally:{practice_id}' if practice_id else f'email:{state["email"]}'
        paid_from = (datetime.utcnow().date() + timedelta(days=TRIAL_DAYS)).isoformat()
        pending_secret = f'onboarding-pending-{DENTALLY_ENV}'
        store = _kv_json(pending_secret)
        store[key] = {
            'principal_email':      state['email'],
            'practice_name':        practice_name,
            'dentally_practice_id': practice_id,
            'attested':             True,
            'paid_from':            paid_from,
            'created_at':           datetime.utcnow().isoformat() + 'Z',
            'status':               'pending_provision',
            'auth_method':          'oauth',
            'oauth':                tokens,
        }
        _kv_set(pending_secret, json.dumps(store))
        _notify_owner_pending(key, store[key])
        app.logger.info("onboarding captured: practice=%s id=%s principal=%s paid_from=%s",
                        practice_name, practice_id, state['email'], paid_from)
        return redirect('/onboarding?status=connected')
    except Exception as e:
        app.logger.exception("onboarding callback failed: %s", e)
        return redirect('/onboarding?status=error')


@app.route('/api/onboarding/dentally/token', methods=['POST'])
def onboarding_token():
    """Manual-token onboarding (no Dentally partner OAuth): the principal creates a Dentally Personal
    Access Token with all read scopes and pastes it here. We run a live PREFLIGHT -- probing every
    endpoint the ingest reads -- so the practice gets real-time confirmation that all the tables we need
    are readable, with a clear message distinguishing an incorrect/expired key from a missing read
    permission. Only once everything is readable do we record a PENDING TRIAL in Key Vault (same
    store/shape as the OAuth path) and email the operator so the throttled onboarding run can be
    scheduled. Public + stateless: gated by the verified-email token + the authority attestation."""
    data    = request.get_json(silent=True) or {}
    payload = _verify_state(data.get('verified', ''), max_age=1800)
    token   = (data.get('token') or '').strip()
    if not payload or payload.get('t') != 'verified':
        return jsonify({'error': 'Please verify your email first.'}), 400
    if not data.get('attested'):
        return jsonify({'error': 'You must confirm you are authorised to share the data.'}), 400
    if len(token) < 20:
        return jsonify({'error': 'Paste the personal access token you created in Dentally.'}), 400
    try:
        # ── Real-time preflight: can this token actually read every table we ingest? ──────────────
        token_valid, checks = _dentally_preflight(token)
        if not token_valid:
            # Incorrect / expired / revoked key -- the token itself was rejected.
            return jsonify({'reason': 'invalid_token',
                            'error': "The access token wasn't accepted. Check you pasted the whole token "
                                     "and that it's still active in Dentally (Settings → Personal "
                                     "Access Tokens)."}), 400
        missing = [g['scope'] for g in checks if any(t['state'] == 'blocked' for t in g['tables'])]
        if missing:
            # Valid key, but a read permission is missing. Don't accept a token that can't read what we
            # need -- return the per-permission checklist so the practice can see exactly what to tick.
            return jsonify({'ok': False, 'reason': 'missing_permissions', 'checks': checks,
                            'error': "Your token can't read some of your Dentally data. Open the token in "
                                     "Dentally, tick every read permission marked below, save, then check "
                                     "again. Note that Treatments sits under “Other” and is not "
                                     "labelled “read” like the rest, so it is easily missed."}), 200

        # ── All readable: capture the practice name, store the pending trial, notify the operator. ──
        practice_id, practice_name = None, payload.get('practice')
        try:
            pr = requests.get(DENTALLY_API_BASE + '/practice', headers={
                'Authorization': 'Bearer ' + token, 'User-Agent': DENTALLY_UA}, timeout=15)
            if pr.ok:
                body = pr.json()
                practices = body.get('practices') or ([body['practice']] if body.get('practice') else [])
                if practices:
                    practice_id   = practices[0].get('id')
                    practice_name = practices[0].get('name') or practice_name
        except requests.RequestException:
            pass  # name is nice-to-have; the preflight already confirmed readability

        # Idempotent per Dentally practice (fall back to the verified email if practice id unknown).
        key = f'dentally:{practice_id}' if practice_id else f'email:{payload["email"]}'
        paid_from = (datetime.utcnow().date() + timedelta(days=TRIAL_DAYS)).isoformat()
        pending_secret = f'onboarding-pending-{DENTALLY_ENV}'
        store = _kv_json(pending_secret)
        store[key] = {
            'principal_email':       payload['email'],
            'practice_name':         practice_name,
            'dentally_practice_id':  practice_id,
            'attested':              True,
            'paid_from':             paid_from,
            'created_at':            datetime.utcnow().isoformat() + 'Z',
            'status':                'pending_provision',
            'auth_method':           'personal_access_token',
            'personal_access_token': token,
        }
        _kv_set(pending_secret, json.dumps(store))
        _notify_owner_pending(key, store[key])
        app.logger.info("onboarding token captured: practice=%s id=%s principal=%s paid_from=%s",
                        practice_name, practice_id, payload['email'], paid_from)
        return jsonify({'ok': True, 'checks': checks})
    except Exception as e:
        return _server_error(e, 'onboarding-token')


# ── Update Dentally token (existing customer, self-serve) ─────────────────────
# A live practice's Dentally Personal Access Token can be regenerated/revoked inside Dentally at any
# time, which silently breaks the nightly ingest (401). Rather than have them email a new token, an
# authenticated practice admin pastes a fresh one here; we run the SAME preflight as onboarding and, only
# if it can read everything, write it straight into KV dentally-tokens-<env>[Tenant_ID] (the exact secret
# the ingest reads). Admin-only, tenant taken from the signed-in user; the token never leaves the vault.

@app.route('/api/dentally/status')
def dentally_status():
    """Report the LIVE health of this tenant's Dentally token, not just whether one exists -- a stored
    token can be silently revoked in Dentally. Probes the token: 'ok' (authenticates), 'invalid' (present
    but rejected -- data has stopped refreshing), 'missing' (none set), 'unknown' (couldn't reach Dentally)."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        conn.close()
        if client_id is None or not tids:
            return jsonify({'error': 'Forbidden'}), 403
        entry = _kv_json(f'dentally-tokens-{DENTALLY_ENV}').get(str(tids[0]), {})
        token = entry.get('token')
        if not token:
            return jsonify({'status': 'missing', 'can_update': bool(maintain)})
        base = (entry.get('base_url') or DENTALLY_API_BASE).rstrip('/')
        status = 'unknown'
        try:
            r = requests.get(base + '/practice', params={'per_page': 1},
                             headers={'Authorization': 'Bearer ' + token, 'User-Agent': DENTALLY_UA}, timeout=15)
            status = 'invalid' if r.status_code in (401, 403) else ('ok' if r.ok else 'unknown')
        except requests.RequestException:
            status = 'unknown'
        return jsonify({'status': status, 'can_update': bool(maintain)})
    except Exception as e:
        return _server_error(e, 'dentally-status')


@app.route('/api/dentally/token', methods=['POST'])
def dentally_update_token():
    """Admin pastes a fresh Dentally PAT; preflight it and (only if fully readable) update the tenant's
    token in KV. Same clear messages as onboarding: incorrect/expired key vs missing read permission."""
    upn, err = _auth()
    if err:
        return err
    token = ((request.get_json(silent=True) or {}).get('token') or '').strip()
    try:
        conn = _fabric_conn()
        cur = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        practice_name = None
        if tids:
            cur.execute("SELECT TOP 1 Tenant_Name FROM Audit.Tenants WHERE Tenant_ID = ?", tids[0])
            row = cur.fetchone()
            practice_name = row[0] if row else None
        conn.close()
    except Exception as e:
        return _server_error(e, 'dentally-token')
    if client_id is None or not tids:
        return jsonify({'error': 'Forbidden'}), 403
    if not maintain:
        return jsonify({'error': 'Only a practice admin can update the Dentally connection.'}), 403
    if len(token) < 20:
        return jsonify({'error': 'Paste the personal access token you created in Dentally.'}), 400
    tenant_id = tids[0]
    try:
        token_valid, checks = _dentally_preflight(token)
        if not token_valid:
            return jsonify({'reason': 'invalid_token',
                            'error': "That token wasn't accepted by Dentally. Check you pasted the whole "
                                     "token and that it's still active (Settings → Personal Access Tokens)."}), 400
        missing = [g['scope'] for g in checks if any(t['state'] == 'blocked' for t in g['tables'])]
        if missing:
            return jsonify({'ok': False, 'reason': 'missing_permissions', 'checks': checks,
                            'error': "That token can't read some of your Dentally data. Tick every read "
                                     "permission marked below in Dentally, save, then check again. Note "
                                     "that Treatments sits under “Other” and is not labelled “read” "
                                     "like the rest, so it is easily missed."}), 200
        # Fully readable -> update the token in place, preserving base_url/name.
        secret = f'dentally-tokens-{DENTALLY_ENV}'
        toks = _kv_json(secret)
        entry = toks.get(str(tenant_id), {})
        entry['base_url'] = entry.get('base_url') or 'https://api.dentally.co/v1'
        entry['name']     = practice_name or entry.get('name')
        entry['token']    = token
        toks[str(tenant_id)] = entry
        _kv_set(secret, json.dumps(toks))
        app.logger.info("dentally token updated by %r for tenant %s", upn, tenant_id)
        return jsonify({'ok': True, 'checks': checks})
    except Exception as e:
        return _server_error(e, 'dentally-token')


# ── Warehouse health monitor (generic build/ingest failure alerting) ──────────
# A small machine endpoint (shared-secret, no user login) that scans the two operational logs for
# failures in a rolling window and emails a summary. Driven by a daily GitHub Actions cron that hits
# dev + prod, so each app checks its OWN warehouse and it runs independently of the nightly build
# (catching build crashes too). Failure signals learned from the logs:
#   * Audit.Process_Execution_Log : Status = 'FAILED'
#   * Audit.Ingest_Log            : Phase LIKE '%FAIL%' OR an HTTP error in Detail (Client/Server Error,
#                                   Unauthorized) -- distinguishes real failures from deliberate throttle-skips.
MONITOR_KEY          = os.environ.get('MONITOR_KEY', '')
MONITOR_NOTIFY       = os.environ.get('MONITOR_NOTIFY', ONBOARDING_NOTIFY)
MONITOR_WINDOW_HOURS = int(os.environ.get('MONITOR_WINDOW_HOURS', '25'))
# How far back a single summary may reach when there is no usable previous-report watermark. Only a
# safety cap -- in steady state the watermark is last night's run, so the email covers this build.
MONITOR_REPORT_MAX_HOURS = int(os.environ.get('MONITOR_REPORT_MAX_HOURS', '168'))
# A practice is nudged about a revoked token at most once per this window. Stops a manual trigger
# colliding with the (often GitHub-delayed) daily cron -- or two cron runs -- from double-sending.
# Daily reminders still get through: consecutive daily runs land ~20-28h apart, above the default.
MONITOR_NUDGE_COOLDOWN_HOURS = int(os.environ.get('MONITOR_NUDGE_COOLDOWN_HOURS', '18'))
# Support address for the customer-facing token-refresh nudge. analytically.info is NOT connected to
# ACS yet, so we can't SEND from it -- the nudge sends from the working managed domain and sets this as
# Reply-To (option B; Reply-To needs no domain verification). Flip the monitor to sender=SUPPORT_FROM
# once analytically.info is verified on ACS.
SUPPORT_FROM         = os.environ.get('SUPPORT_FROM', 'Support@Analytically.info')


def _monitor_email_body(proc, ing, since):
    # 'since' is the previous report's watermark, so this lists THIS build's real errors only --
    # already-reported rows and already-fixed token 401s are filtered out by the caller.
    lines = [f"Warehouse health check ({APP_ENV}) — new failures since {since}.\n"]
    if proc:
        lines.append(f"Process_Execution_Log — {len(proc)} FAILED:")
        for r in proc[:20]:
            lines.append(f"  {r['when']}  {r['name'] or '(unnamed)'}  {r['error'][:160]}")
        if len(proc) > 20:
            lines.append(f"  … +{len(proc) - 20} more")
        lines.append("")
    if ing:
        # Group the (often many, near-identical) ingest rows by tenant + error signature.
        groups = {}
        for r in ing:
            sig = (r['detail'].split(' for url')[0] or r['phase'])[:70]
            g = groups.setdefault((r['tenant'], sig), [])
            g.append(r['entity'])
        lines.append(f"Ingest_Log — {len(ing)} failure row(s), {len(groups)} distinct:")
        for (tenant, sig), entities in list(groups.items())[:20]:
            lines.append(f"  tenant {tenant}: {len(entities)} entit{'y' if len(entities)==1 else 'ies'} — {sig}")
            lines.append(f"      ({', '.join(entities[:8])}{' …' if len(entities) > 8 else ''})")
        lines.append("")
    lines.append("Investigate in Audit.Unified_Log. (Dentally 401s: a practice admin can refresh the token in the app under Settings → Dentally.)")
    return "\n".join(lines)


def _tenant_primary_email(tenant_id):
    """The practice's SINGLE main account (Input.Billing_Contact.Primary_Email, else Invoice_Email) from
    the AppDB -- the same contact that receives invoices. Returns one address or None (don't guess/blast)."""
    try:
        conn = _appdb_conn()
        cur = conn.cursor()
        cur.execute("SELECT TOP 1 Primary_Email, Invoice_Email FROM Input.Billing_Contact WHERE Tenant_ID = ?",
                    tenant_id)
        row = cur.fetchone()
        conn.close()
        if not row:
            return None
        return ((row[0] or row[1] or '').strip() or None)
    except Exception as e:
        app.logger.warning("primary-email lookup failed for tenant %s: %s", tenant_id, e)
        return None


def _principal_token_email_body():
    """Customer-facing nudge: their Dentally token was rejected, here's how to fix it (deep link to the
    Settings → Dentally screen). Sent PROD-only from the monitor."""
    link = os.environ.get('APP_URL', 'https://app.analytically.info').rstrip('/') + '/?settings=dentally'
    return (
        "Your Analytically data has stopped updating.\n\n"
        "Dentally is no longer accepting the access token for your practice, so your overnight data "
        "refresh has stopped. This almost always means the token was regenerated in Dentally.\n\n"
        "It takes about a minute to fix:\n"
        "  1. In Dentally: Settings -> Personal Access Tokens -> New personal access token. Tick EVERY "
        "read permission -- AND 'Other -> Treatments', which is not labelled 'read' like the rest and is "
        "easily missed. Save, and copy the token.\n"
        f"  2. In Analytically: open Settings -> Dentally and paste it in --\n     {link}\n\n"
        "We'll check the token can read your data before saving, and your reports will catch up on the "
        "next overnight refresh.\n"
    )


@app.route('/api/monitor/health', methods=['POST'])
def monitor_health():
    """Scan Audit.Process_Execution_Log + Audit.Ingest_Log and email a summary of REAL, NEW failures.

    Two different spans, deliberately: the summary covers only what has happened since the previous
    MONITOR row (in practice this build), so a failure is reported once and never re-listed; the
    revoked-token DETECTION still looks across MONITOR_WINDOW_HOURS, because deciding whether a token
    is still broken needs the 401 history. 401s from a tenant since proven working are excluded from
    the summary entirely. Shared-secret auth (X-Monitor-Key); fails closed if MONITOR_KEY unset."""
    if not MONITOR_KEY or not hmac.compare_digest(request.headers.get('X-Monitor-Key', ''), MONITOR_KEY):
        return jsonify({'error': 'Unauthorized'}), 401
    try:
        since = (datetime.utcnow() - timedelta(hours=MONITOR_WINDOW_HOURS)).strftime('%Y-%m-%dT%H:%M:%S')
        conn = _fabric_conn()
        cur = conn.cursor()
        # REPORT on this build only. The monitor is the build's own last step, so the previous MONITOR
        # row marks exactly where the last report stopped -- anything at or before it has already been
        # emailed once. Reporting on the rolling window instead drags the PREVIOUS night's rows into
        # tonight's summary, which is how tenant 100 was still listed as a connection failure on
        # 2026-09-08, a day after its token was fixed. DETECTION below keeps the full window, because
        # deciding whether a token is still broken needs the 401 history, not just this run.
        cur.execute("SELECT MAX(Logged_At) FROM Audit.Ingest_Log "
                    "WHERE Phase IN ('MONITOR','MONITOR_SKIP')")
        row = cur.fetchone()
        last_report = row[0] if row else None
        # Never reach back further than the cap: a missing or ancient watermark (log trimmed, first
        # ever run, monitor offline for weeks) must not dump an unbounded backlog into one email.
        cap = datetime.utcnow() - timedelta(hours=MONITOR_REPORT_MAX_HOURS)
        if last_report is None:
            report_from = datetime.utcnow() - timedelta(hours=MONITOR_WINDOW_HOURS)
        else:
            report_from = max(last_report, cap)
        report_since = report_from.strftime('%Y-%m-%dT%H:%M:%S')
        cur.execute(
            "SELECT Start_Time, Process_Name, LEFT(ISNULL(Error_Message,''),200) "
            "FROM Audit.Process_Execution_Log WHERE Status = 'FAILED' AND Start_Time >= ? "
            "ORDER BY Start_Time DESC", report_since)
        proc = [{'when': str(r[0]), 'name': r[1], 'error': r[2] or ''} for r in cur.fetchall()]
        cur.execute(
            "SELECT Logged_At, Tenant_ID, Entity, Phase, LEFT(ISNULL(Detail,''),200) "
            "FROM Audit.Ingest_Log WHERE Logged_At >= ? AND ("
            "Phase LIKE '%FAIL%' OR Detail LIKE '%Client Error%' OR Detail LIKE '%Server Error%' "
            "OR Detail LIKE '%Unauthorized%') ORDER BY Logged_At DESC", report_since)
        ing = [{'when': str(r[0]), 'tenant': r[1], 'entity': r[2], 'phase': r[3] or '', 'detail': r[4] or ''}
               for r in cur.fetchall()]
        # A revoked Dentally token shows as 401/Unauthorized on its entities. But we must NOT keep nagging
        # a practice whose token is already fixed: flag a tenant only if there is NO successful Dentally
        # fetch AFTER its most recent 401 -- i.e. its current state is broken, not merely "had a failure
        # in the window". "Success" = a Dentally entity that got past auth and pulled data: phases
        # DONE / PAGE / WINDOW (Ingest_Dentally). A 401 stops at SKIP, so those never appear for a dead
        # token. Xero entities (xero_*) are excluded so a working Xero feed can't mask a dead Dentally
        # token. Once the next run succeeds the reminders stop on their own; a stale in-window 401 never
        # re-fires after a fix. (FETCH/WROTE/EMPTY are Xero's success phases, kept for completeness.)
        cur.execute(
            "SELECT Tenant_ID, "
            "  MAX(CASE WHEN (Detail LIKE '%401%' OR Detail LIKE '%Unauthorized%') "
            "           AND Entity NOT LIKE 'xero[_]%' THEN Logged_At END) AS last_401, "
            "  MAX(CASE WHEN Phase IN ('DONE','PAGE','WINDOW','FETCH','WROTE','EMPTY') "
            "           AND Entity NOT LIKE 'xero[_]%' THEN Logged_At END) AS last_ok "
            "FROM Audit.Ingest_Log WHERE Logged_At >= ? AND Tenant_ID IS NOT NULL "
            "GROUP BY Tenant_ID", since)
        bad_token_tenants = sorted(r[0] for r in cur.fetchall()
                                   if r[1] is not None and (r[2] is None or r[2] < r[1]))
        conn.close()
        # One recipient per bad-token tenant: the practice's MAIN account (Input.Billing_Contact, AppDB).
        primary = {tid: _tenant_primary_email(tid) for tid in bad_token_tenants}

        # Only alert the operator on something ACTIONABLE: a process failure, an UNRESOLVED bad token, or
        # an ingest error that isn't a (possibly already-resolved) token 401. So a practice that fixes its
        # token stops BOTH the nudge and the operator summary once stale 401s are all that remain.
        _is_token_401 = lambda d: ('401' in d or 'Unauthorized' in d)
        # Drop 401s belonging to a tenant that is NOT in bad_token_tenants. Absence from that list
        # means a later successful Dentally fetch proved the token now works, so those rows are a
        # record of a fixed problem, not a real error -- they must not be counted or listed.
        # A 401 with no Tenant_ID is NOT swept up: it cannot be attributed to a practice token, so
        # there is nothing proving it resolved (it is more likely an infrastructure auth fault).
        real_ing = [r for r in ing
                    if not _is_token_401(r['detail'])
                    or r['tenant'] is None
                    or r['tenant'] in bad_token_tenants]
        suppressed = len(ing) - len(real_ing)
        # real_ing has already had the resolved 401s removed, so anything still in it is a live
        # error and worth an email -- including a 401 that carries no tenant.
        actionable = bool(proc) or bool(bad_token_tenants) or bool(real_ing)

        total = len(proc) + len(real_ing)
        # PROD ONLY: never email real customers (or the operator) from a non-prod app.
        emails_on = (APP_ENV == 'prod')
        notified = []
        if emails_on:
            if actionable:
                _send_email(MONITOR_NOTIFY,
                            f"Warehouse health: {total} failure(s) in the last {MONITOR_WINDOW_HOURS}h",
                            _monitor_email_body(proc, real_ing, report_since))
            if bad_token_tenants:
                # Per-tenant cooldown: never nudge the same practice twice inside
                # MONITOR_NUDGE_COOLDOWN_HOURS, so overlapping triggers (manual + delayed cron, a
                # re-run, a double-fire) collapse to a single email. State persists in Key Vault.
                now = datetime.utcnow()
                nudge_state = _kv_json('monitor-nudge-state')
                state_changed = False
                for tid in bad_token_tenants:
                    em = primary.get(tid)
                    if not em:
                        app.logger.warning("monitor: tenant %s has a bad token but no Billing_Contact main email", tid)
                        continue
                    last = nudge_state.get(str(tid))
                    if last:
                        try:
                            if now - datetime.fromisoformat(last) < timedelta(hours=MONITOR_NUDGE_COOLDOWN_HOURS):
                                app.logger.warning("monitor: tenant %s within %sh nudge cooldown -- skipping",
                                                   tid, MONITOR_NUDGE_COOLDOWN_HOURS)
                                continue
                        except ValueError:
                            pass   # unparseable stored value -> treat as no prior nudge
                    _send_email(em, "Action needed: your Analytically data has stopped updating",
                                _principal_token_email_body(), reply_to=SUPPORT_FROM)
                    notified.append(em)
                    nudge_state[str(tid)] = now.isoformat()
                    state_changed = True
                if state_changed:
                    _kv_set('monitor-nudge-state', json.dumps(nudge_state))
        app.logger.warning("monitor(%s): since %s -- %d process + %d ingest failure(s) "
                           "(%d resolved 401(s) suppressed); bad-token tenants=%s; principal emails=%s",
                           APP_ENV, report_since, len(proc), len(real_ing), suppressed,
                           bad_token_tenants,
                           len(notified) if emails_on else 'suppressed(non-prod)')
        return jsonify({'window_hours': MONITOR_WINDOW_HOURS, 'process_failures': len(proc),
                        'ingest_failures': len(real_ing), 'failures': total,
                        'report_since': report_since, 'resolved_401_suppressed': suppressed,
                        'bad_token_tenants': bad_token_tenants,
                        'principals_notified': len(notified), 'emails_enabled': emails_on})
    except Exception as e:
        return _server_error(e, 'monitor-health')


# ── Helpers ───────────────────────────────────────────────────────────────────

def _is_staff(upn):
    """Our own people, by mailbox domain -- the same test the cancel exemption already uses.

    Deliberately not a flag in Security.Application_Users: that table is fed from AppDB by the
    nightly sync, so a flag there would be editable through the same path a practice admin uses to
    manage their own team. The domain is asserted by Entra at sign-in and cannot be granted from
    inside the product.
    """
    return (upn or '').lower().endswith('@analytically.info')


def _acting_client_id(upn):
    """The practice a support login has picked, or None.

    STAFF ONLY, and re-checked on every request rather than trusted from a previous one -- the
    header is client-supplied, so it is an assertion of intent, never of permission. A practice
    admin sending the same header gets None and stays in their own practice.
    """
    if not _is_staff(upn) or not has_request_context():
        return None
    return (request.headers.get('X-Acting-Client') or '').strip() or None


def _get_user_info(cur, upn):
    """Returns (display_name, client_id, tenant_ids, maintain_targets) or (None, None, [], False).

    Fails closed THREE ways: no row at all, no ACTIVE tenant, or a row that grants nothing --
    no module and no Maintain_Targets.

    That last check is the important one. Security.Application_Users is meant to hold
    access-holders ONLY (see Meta.usp_Sync_Access_From_AppDB *02), but an all-zero row left
    behind by a failed sync still returned a valid client_id and tenant list. Reports were safe
    (embed-token gates per module) and admin routes were safe (they check maintain), but the
    /api/targets routes gate on client_id alone -- so a stale row could READ and WRITE a
    practice's targets. Prod carried 61 such rows while its hourly sync was unknowingly running
    against dev. Checking the flags here means a stale row is inert whatever the sync is doing.
    """
    cols = ", ".join(_ALL_MODULE_COLS)
    cur.execute(
        "SELECT Display_Name, Client_ID, Maintain_Targets, " + cols + " "
        "FROM Security.Application_Users WHERE LOWER(User_UPN) = LOWER(?)",
        upn,
    )
    row = cur.fetchone()
    if not row:
        return None, None, [], False
    display_name, client_id, maintain_targets = row[0], row[1], bool(row[2])
    if not maintain_targets and not any(bool(v) for v in row[3:]):
        return None, None, [], False   # row grants nothing -> treat as unprovisioned
    # OUR OWN STAFF MAY ACT AS ANOTHER PRACTICE. Investigating a practice used to mean running SQL
    # to repoint the support login's Client_ID; the picker does it per request instead. It is applied
    # HERE, at the one function every route resolves identity through, so the whole app moves
    # together -- reports, Subscriptions, invoices, Admin -- and there is exactly one place the
    # restriction has to be right, rather than a tenant argument on every endpoint to forget.
    #
    # It changes only WHICH practice, never WHAT the support login may do: display_name, the module
    # flags and Maintain_Targets still come from their own row above.
    acting = _acting_client_id(upn)
    if acting is not None and str(acting) != str(client_id):
        # RESOLVE IT AGAINST THE DATABASE BEFORE USING IT, and compare as text. The header arrives
        # as a string while Client_ID is an int, so passing it straight to the tenant lookup made
        # SQL Server raise a conversion error on any non-numeric value -- a 500 from an unhandled
        # driver exception, not the clean refusal this was supposed to be. Casting also keeps the
        # check working if the column type ever changes. The canonical value comes back from the
        # row, so client_id stays the type the rest of the app expects.
        # Resolved against the ACCESS table, not Audit.Tenants. A client is valid to act as if
        # it has at least one active tenant GRANTED to it -- which is not the same as owning
        # one. The Analytically client owns no tenant at all and can see every one of them.
        cur.execute("SELECT TOP 1 a.Client_ID FROM Security.Client_Tenant_Access a "
                    "JOIN Audit.Tenants t ON t.Tenant_ID = a.Tenant_ID "
                    "WHERE CAST(a.Client_ID AS VARCHAR(64)) = ? "
                    "AND ISNULL(t.Is_Active, 1) = 1", str(acting))
        row = cur.fetchone()
        if not row:
            app.logger.warning('staff %s asked for unknown/inactive client %r', upn, acting)
            return None, None, [], False
        app.logger.info('staff %s acting as client %s', upn, row[0])
        client_id = row[0]

    # ==> OWNERSHIP AND VISIBILITY ARE DIFFERENT THINGS. <== This read Audit.Tenants.Client_ID,
    # which is a COLUMN on the tenant -- so a tenant belonged to exactly one client and could
    # therefore be seen by exactly one client. One client owning several tenants worked; one
    # tenant being visible to several clients did not, and that is what our own people need in
    # order to see every practice.
    #
    # Audit.Tenants.Client_ID still says who OWNS a tenant, which is what billing, subscriptions
    # and invoicing care about. Security.Client_Tenant_Access says who may SEE it. Seeded so that
    # every client keeps access to what it owns, so this change grants nobody anything new.
    cur.execute(
        "SELECT t.Tenant_ID FROM Security.Client_Tenant_Access a "
        "JOIN Audit.Tenants t ON t.Tenant_ID = a.Tenant_ID "
        "WHERE a.Client_ID = ? AND ISNULL(t.Is_Active, 1) = 1",
        client_id,
    )
    tids = [r[0] for r in cur.fetchall()]
    if not tids:
        # No ACTIVE tenant -- a cancelled subscription, or a staff override naming a client that
        # does not exist. Fails closed either way: callers read client_id None as Forbidden, so a
        # bad override yields 403 rather than quietly falling back to the support login's own
        # practice and showing one practice's figures under another's name.
        return None, None, [], False
    return display_name, client_id, tids, maintain_targets


# Section/report key -> Application_Users column. The App menu keys match the
# /api/embed-token 'report' names, so this one map gates both the visible menu
# (via /api/me) and token minting (via /api/embed-token).
_ACCESS_COLUMNS = [
    ('home',       'Access_Home'),
    ('revenue',    'Access_Revenue'),
    ('patient',    'Access_Patient'),
    ('scheduling', 'Access_Schedule'),
    ('clinical',   'Access_Clinical'),
    ('nhs',        'Access_NHS'),
    ('day_book',   'Access_Day_Book'),
    ('finance',    'Access_Finance'),
    ('my_data',    'Access_My_Data'),
    ('marketing',  'Access_Marketing'),
]

# Subscription profiles: preset module flags + Maintain_Targets. Billing basis = the assigned
# profile's price (Config.Access_Profile). The Team screen assigns one profile per user.
_PROFILES = {
    'full':         {'label': 'All reports',  'modules': {'Access_Home','Access_Revenue','Access_Patient','Access_Schedule','Access_Clinical','Access_NHS','Access_Day_Book','Access_Finance','Access_My_Data','Access_Marketing'}, 'maintain_targets': True,  'desc': 'Every report and dashboard.'},
    'clinician':    {'label': 'Clinician',    'modules': {'Access_My_Data'}, 'maintain_targets': False, 'desc': 'The clinician’s OWN data only (My Data) — no other reports shown.'},
    'front_office': {'label': 'Front Office', 'modules': {'Access_Home','Access_Schedule','Access_Patient'}, 'maintain_targets': False, 'desc': 'Focuses on the tasks that help the practice run more efficiently.'},
    'no_access':    {'label': 'No Access',    'modules': set(), 'maintain_targets': False, 'desc': 'No access to the app.'},
}
_ALL_MODULE_COLS = [c for _, c in _ACCESS_COLUMNS]

def _derive_profile(enabled_cols):
    """Map a set of enabled Access_* columns to a profile key, else 'custom'."""
    s = set(enabled_cols)
    for key, p in _PROFILES.items():
        if p['modules'] == s:
            return key
    return 'custom'


def _get_user_access(cur, upn):
    """Returns ({section_key: bool}, practitioner_full_name). A missing row or a
    NULL flag is treated as False (fail-closed: unset = no access)."""
    cols = ', '.join(c for _, c in _ACCESS_COLUMNS)
    cur.execute(
        f"SELECT {cols}, Practitioner_Full_Name "
        "FROM Security.Application_Users WHERE LOWER(User_UPN) = LOWER(?)",
        upn,
    )
    row = cur.fetchone()
    if not row:
        return {k: False for k, _ in _ACCESS_COLUMNS}, None
    access = {k: bool(row[i]) for i, (k, _) in enumerate(_ACCESS_COLUMNS)}
    return access, row[len(_ACCESS_COLUMNS)]


# ── Targets ───────────────────────────────────────────────────────────────────

@app.route('/api/targets', methods=['GET'])
def get_targets():
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        if client_id is None:
            conn.close()
            return jsonify({'error': 'Forbidden'}), 403

        cur.execute(
            "SELECT Metric_Key, Display_Name, Section, Format_Type, Range_Type "
            "FROM Config.Metric_Definitions WHERE Is_Active = 1 ORDER BY Display_Order"
        )
        metrics = [
            {'key': r[0], 'display_name': r[1], 'section': r[2],
             'format_type': r[3], 'range_type': r[4]}
            for r in cur.fetchall()
        ]

        tenants = {}
        targets = {}
        if tids:
            ph = ','.join(['?'] * len(tids))
            cur.execute(
                f"SELECT Tenant_ID, Tenant_Name FROM Audit.Tenants "
                f"WHERE Tenant_ID IN ({ph}) AND Is_Active = 1 ORDER BY Tenant_ID",
                tids,
            )
            tenants = [{'id': r[0], 'name': r[1]} for r in cur.fetchall()]

            cur.execute(
                f"SELECT Tenant_ID, Metric, Target_Value, Variance FROM Input.Targets "
                f"WHERE Tenant_ID IN ({ph}) "
                f"AND Period_Type = 'all_time' AND Period_Value = 'all' "
                f"AND Site_ID IS NULL AND Practitioner_ID IS NULL",
                tids,
            )
            for r in cur.fetchall():
                targets[f"{r[0]}|{r[1]}"] = {
                    'value':    float(r[2]) if r[2] is not None else None,
                    'variance': float(r[3]) if r[3] is not None else None,
                }

        conn.close()
        return jsonify({'metrics': metrics, 'tenants': tenants, 'targets': targets})
    except Exception as e:
        return _server_error(e, 'get_targets')


@app.route('/api/targets', methods=['POST'])
def save_targets():
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn(autocommit=True)
        cur  = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        if client_id is None:
            conn.close()
            return jsonify({'error': 'Forbidden'}), 403

        rows         = request.get_json(force=True) or []
        allowed_tids = set(tids)

        valid = [
            (int(r['tenant_id']), str(r['metric']), r.get('value'), r.get('variance'))
            for r in rows if int(r['tenant_id']) in allowed_tids
        ]

        if valid:
            cur.fast_executemany = True
            cur.executemany(
                "DELETE FROM Input.Targets "
                "WHERE Tenant_ID = ? AND Metric = ? "
                "AND Period_Type = 'all_time' AND Period_Value = 'all' "
                "AND Site_ID IS NULL AND Practitioner_ID IS NULL",
                [(tid, metric) for tid, metric, _, _ in valid],
            )
            inserts = [
                (tid, metric, float(value),
                 float(variance) if variance is not None else None)
                for tid, metric, value, variance in valid if value is not None
            ]
            if inserts:
                cur.executemany(
                    "INSERT INTO Input.Targets "
                    "(Tenant_ID, Site_ID, Practitioner_ID, Metric, Period_Type, Period_Value, "
                    " Target_Value, Variance, DW_Created_At, DW_Updated_At) "
                    "VALUES (?, NULL, NULL, ?, 'all_time', 'all', ?, ?, GETUTCDATE(), GETUTCDATE())",
                    inserts,
                )

        conn.close()
        return jsonify({'ok': True})
    except Exception as e:
        return _server_error(e, 'save_targets')


# ── Associate pay (per-practitioner %) — admin Settings screen ────────────────

@app.route('/api/practice-config', methods=['GET'])
def get_practice_config():
    """Per-tenant practice settings. FY_Start_Month = the month (1-12) the practice financial year
    starts (default 4 = April). NHS FY is always Apr-Mar and is NOT affected by this. Owner-only."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn(); cur = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        conn.close()
        if client_id is None:
            return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            return jsonify({'error': 'Only a practice admin can view settings'}), 403
        fy_start = 4
        if tids:
            ac = _appdb_conn(); acur = ac.cursor()
            acur.execute("SELECT FY_Start_Month FROM Input.Practice_Config WHERE Tenant_ID = ?", tids[0])
            row = acur.fetchone(); ac.close()
            if row and row[0]:
                fy_start = int(row[0])
        return jsonify({'fy_start_month': fy_start})
    except Exception as e:
        return _server_error(e, 'get_practice_config')


@app.route('/api/practice-config', methods=['POST'])
def save_practice_config():
    """Set the practice financial-year start month (1-12) for the tenant(s). Owner-only."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn(); cur = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        conn.close()
        if client_id is None:
            return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            return jsonify({'error': 'Only a practice admin can change settings'}), 403
        body = request.get_json(force=True) or {}
        try:
            m = int(body.get('fy_start_month'))
        except (TypeError, ValueError):
            return jsonify({'error': 'Invalid month'}), 400
        if not (1 <= m <= 12):
            return jsonify({'error': 'Month must be 1-12'}), 400
        ac = _appdb_conn(autocommit=True); acur = ac.cursor()
        for t in tids:
            acur.execute("DELETE FROM Input.Practice_Config WHERE Tenant_ID = ?", t)
            acur.execute("INSERT INTO Input.Practice_Config (Tenant_ID, FY_Start_Month, Updated_At, Updated_By) "
                         "VALUES (?, ?, SYSUTCDATETIME(), ?)", t, m, upn)
        ac.close()
        return jsonify({'ok': True})
    except Exception as e:
        return _server_error(e, 'save_practice_config')


@app.route('/api/practitioner-pay', methods=['GET'])
def get_practitioner_pay():
    """Active fee-earners for the tenant(s) + their current associate % (or null)."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None:
            conn.close()
            return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            conn.close()
            return jsonify({'error': 'Only a practice admin can view associate pay'}), 403
        practitioners = []
        if tids:
            ph = ','.join(['?'] * len(tids))
            cur.execute(
                f"SELECT p.Tenant_ID, p.Practitioner_ID, p.Full_Name, p.Role, p.Custom_Role "
                f"FROM Gold.Dim_Practitioners p "
                f"WHERE p.Tenant_ID IN ({ph}) AND p.Active = 1 AND p.pk_Practitioner > 0 "
                f"ORDER BY p.Full_Name",
                tids,
            )
            practitioners = [
                {'tenant_id': r[0], 'practitioner_id': r[1], 'name': r[2], 'dentally_role': r[3],
                 'role': r[4] or r[3], 'associate_pct': None, 'fte': None}
                for r in cur.fetchall()
            ]
        conn.close()
        # Associate_Pct / FTE are owner inputs -> live in AppDB (source of truth; survive WH
        # redeploys, synced into WH each build). Overlay them onto the warehouse practitioner list.
        if practitioners:
            ac = _appdb_conn(); acur = ac.cursor(); aph = ','.join(['?'] * len(tids))
            acur.execute(
                f"SELECT Tenant_ID, Practitioner_ID, Associate_Pct, FTE "
                f"FROM Input.Practitioner_Pay WHERE Tenant_ID IN ({aph})",
                tids,
            )
            pay = {(row[0], int(row[1])): row for row in acur.fetchall()}
            ac.close()
            for p in practitioners:
                row = pay.get((p['tenant_id'], int(p['practitioner_id'])))
                if row:
                    p['associate_pct'] = float(row[2]) if row[2] is not None else None
                    p['fte'] = float(row[3]) if row[3] is not None else None
        return jsonify({'practitioners': practitioners})
    except Exception as e:
        return _server_error(e, 'get_practitioner_pay')


@app.route('/api/practitioner-pay', methods=['POST'])
def save_practitioner_pay():
    """Upsert each practitioner's associate %. A blank/null clears it (DELETE only)."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None:
            conn.close()
            return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            conn.close()
            return jsonify({'error': 'Only a practice admin can set associate pay'}), 403

        rows    = request.get_json(force=True) or []
        allowed = set(tids)
        # (tenant_id, practitioner_id, pct-or-None, fte-or-None), only for the caller's tenant(s).
        valid = []
        for r in rows:
            try:
                tid = int(r['tenant_id']); pid = int(r['practitioner_id'])
            except (KeyError, TypeError, ValueError):
                continue
            if tid not in allowed:
                continue
            pct = r.get('associate_pct'); pctf = None
            if pct not in (None, ''):
                try:
                    pctf = float(pct)
                except (TypeError, ValueError):
                    continue
                if not (0 <= pctf <= 100):
                    continue
            fte = r.get('fte'); ftef = None
            if fte not in (None, ''):
                try:
                    ftef = float(fte)
                except (TypeError, ValueError):
                    continue
                if not (0 <= ftef <= 2):
                    continue
            valid.append((tid, pid, pctf, ftef))

        conn.close()
        # Write to AppDB (source of truth; survives WH redeploys, synced into WH each build).
        if valid:
            ac = _appdb_conn(autocommit=True); acur = ac.cursor(); acur.fast_executemany = True
            acur.executemany(
                "DELETE FROM Input.Practitioner_Pay WHERE Tenant_ID = ? AND Practitioner_ID = ?",
                [(t, p) for t, p, _, _ in valid],
            )
            inserts = [(t, p, pc, ft, upn) for t, p, pc, ft in valid if pc is not None or ft is not None]
            if inserts:
                acur.executemany(
                    "INSERT INTO Input.Practitioner_Pay "
                    "(Tenant_ID, Practitioner_ID, Associate_Pct, FTE, Updated_At, Updated_By) "
                    "VALUES (?, ?, ?, ?, SYSUTCDATETIME(), ?)",
                    inserts,
                )
            ac.close()
        return jsonify({'ok': True})
    except Exception as e:
        return _server_error(e, 'save_practitioner_pay')


# ── Team / Access management (owner self-service subscription) ────────────────

@app.route('/api/team', methods=['GET'])
def get_team():
    """Roster (Dim_Users, front office included) x each person's current subscription profile +
    My Data practitioner, the profile catalogue (with price), the practitioner pick-list, and a
    monthly-cost preview. Owner-only (Maintain_Targets). The caller's own row is flagged locked."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            conn.close(); return jsonify({'error': 'Only a practice admin can manage the team'}), 403
        cur.execute("SELECT p.Profile_Key, p.Monthly_Price FROM Billing.Profile_Pricing p "
                    "JOIN (SELECT Profile_Key, MAX(Valid_From) vf FROM Billing.Profile_Pricing "
                    "WHERE Valid_From <= CAST(SYSUTCDATETIME() AS DATE) AND (Valid_To IS NULL OR Valid_To >= CAST(SYSUTCDATETIME() AS DATE)) "
                    "GROUP BY Profile_Key) m ON m.Profile_Key = p.Profile_Key AND m.vf = p.Valid_From")
        _prices = {r[0]: float(r[1]) for r in cur.fetchall()}
        profiles = [{'key': k, 'name': v['label'], 'desc': v.get('desc', ''), 'price': _prices.get(k, 0.0)} for k, v in _PROFILES.items()]
        people = []
        billing = {'primary_email': '', 'invoice_email': ''}
        if tids:
            ph = ','.join(['?'] * len(tids))
            # ACTIVE staff only, keyed on Dentally's permission_level. Dentally has no 'active' field
            # on a user -- permission_level IS the activity signal (0 = deactivated), which is why we
            # test it rather than anything on the practitioner record.
            #
            # Previously this used Silver.Practitioners.Practitioner_Active, on the assumption that
            # front office "have no such flag, so are kept". That was wrong: front-office staff often
            # DO have a practitioner record, and it gets deactivated when they stop being a bookable
            # diary entry -- while their user account stays live. On tenant 100 that silently hid two
            # active administrators (permission_level 4) from the subscriptions roster.
            #
            # COALESCE order matters. Gold.Dim_Users.Permission_Level is the correct source, but it is
            # only populated from the first build after Bronze.usp_Load_Users *04 (it was never staged,
            # so it reads NULL for every pre-existing row). Until then fall back to the same value as
            # carried on the practitioner record, then to 1 (assume active) for the many users who have
            # no practitioner record at all. Once the backfill lands the first term simply wins.
            # Dim_Practitioners still supplies the deduced My Data practitioner name.
            cur.execute(
                f"SELECT u.Tenant_ID, u.Email, u.Full_Name, u.Role, u.Site_ID, dp.practitioner "
                f"FROM Gold.Dim_Users u "
                f"LEFT JOIN (SELECT Tenant_ID, User_ID, MAX(User_Permission_Level) AS perm "
                f"           FROM Silver.Practitioners GROUP BY Tenant_ID, User_ID) sp "
                f"           ON sp.Tenant_ID = u.Tenant_ID AND sp.User_ID = u.bk_User_ID "
                f"LEFT JOIN (SELECT Tenant_ID, User_ID, MAX(Full_Name) AS practitioner "
                f"           FROM Gold.Dim_Practitioners WHERE pk_Practitioner > 0 AND User_ID IS NOT NULL "
                f"           GROUP BY Tenant_ID, User_ID) dp ON dp.Tenant_ID = u.Tenant_ID AND dp.User_ID = u.bk_User_ID "
                f"WHERE u.Tenant_ID IN ({ph}) AND u.Is_Current = 1 AND NULLIF(LTRIM(RTRIM(u.Email)),'') IS NOT NULL "
                f"  AND COALESCE(u.Permission_Level, sp.perm, 1) > 0 "
                f"ORDER BY CASE "
                f"           WHEN LOWER(u.Role) LIKE '%dentist%'          THEN 1 "
                f"           WHEN LOWER(u.Role) LIKE '%hygien%'           THEN 2 "
                f"           WHEN LOWER(u.Role) LIKE '%practice manager%' THEN 3 "
                f"           WHEN LOWER(u.Role) LIKE '%nurse%'            THEN 4 "
                f"           ELSE 5 END, u.Full_Name", tids)
            roster = [{'tenant_id': r[0], 'email': r[1], 'name': r[2], 'dentally_role': r[3],
                       'site_id': r[4], 'practitioner': r[5]} for r in cur.fetchall()]
            conn.close()
            # Current subscription state comes from AppDB (source of truth -- reflects the owner's
            # latest edits, which may not have synced to the warehouse auth copy yet).
            ac = _appdb_conn(); acur = ac.cursor()
            acur.execute("SELECT LOWER(User_UPN), " + ", ".join(_ALL_MODULE_COLS)
                         + ", Profile_Key, Maintain_Targets FROM Input.Application_Users")
            n = len(_ALL_MODULE_COLS)
            au = {}
            for r in acur.fetchall():
                enabled = {_ALL_MODULE_COLS[i] for i in range(n) if r[1 + i]}
                au[r[0]] = {'enabled': enabled, 'profile_key': r[1 + n], 'admin': bool(r[2 + n])}
            bph = ','.join(['?'] * len(tids))
            acur.execute(f"SELECT Tenant_ID, Primary_Email, Invoice_Email FROM Input.Billing_Contact WHERE Tenant_ID IN ({bph})", tids)
            bc = {r[0]: {'primary': (r[1] or ''), 'invoice': (r[2] or '')} for r in acur.fetchall()}
            ac.close()
            b0 = bc.get(tids[0], {'primary': '', 'invoice': ''})
            billing = {'primary_email': b0['primary'], 'invoice_email': b0['invoice']}
            for m in roster:
                a = au.get((m['email'] or '').lower())
                m['profile'] = (a['profile_key'] or _derive_profile(a['enabled'])) if a else 'no_access'
                m['is_self'] = (m['email'] or '').lower() == (upn or '').lower()
                m['is_primary'] = (m['email'] or '').lower() == (b0['primary'] or '').lower()
                m['is_admin'] = True if m['is_self'] else (a['admin'] if a else False)
                people.append(m)
        else:
            conn.close()
        return jsonify({'people': people, 'profiles': profiles, 'billing': billing})
    except Exception as e:
        return _server_error(e, 'get_team')


# Stripe's invoice status -> what a practice should be told. Stripe's own words are right for
# us but not for them: "draft" is an internal state meaning we have not issued it yet, and
# "uncollectible" is accountancy language for "this did not get paid".
_INVOICE_STATUS_LABEL = {
    'draft':         'Not yet issued',
    'open':          'Due',
    'paid':          'Paid',
    'void':          'Cancelled',
    'uncollectible': 'Unpaid',
}


@app.route('/api/invoices', methods=['GET'])
def get_invoices():
    """Billing history for the caller's practice: Billing.Invoice_Line grouped by month (each line is a
    subscribed user; the first part-month at sign-up is pro-rated), with the Stripe status of each
    month overlaid from Billing.Stripe_Invoice. Read-only, owner-only. A month with lines and no
    status simply has not been through the billing run yet -- that is the normal state, not a
    fault; free-forever / trial months have no lines at all."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            conn.close(); return jsonify({'error': 'Only a practice admin can view invoices'}), 403
        plabels = {k: v['label'] for k, v in _PROFILES.items()}
        months, by_month, order = [], {}, []
        if tids:
            ph = ','.join(['?'] * len(tids))
            cur.execute(
                f"SELECT Year_Month, Display_Name, User_UPN, Profile_Key, Value "
                f"FROM Billing.Invoice_Line WHERE Tenant_ID IN ({ph}) "
                f"ORDER BY Year_Month DESC, Value DESC, Display_Name", tids)
            for ym, name, email, pk, val in cur.fetchall():
                if ym not in by_month:
                    by_month[ym] = {'year_month': ym, 'total': 0.0, 'lines': [],
                                    'status': None, 'status_label': None}
                    order.append(ym)
                by_month[ym]['lines'].append({'name': name or email, 'email': email,
                                              'profile': plabels.get(pk, pk), 'value': float(val or 0)})
                by_month[ym]['total'] += float(val or 0)
            # Overlay what Stripe knows. Deliberately a SEPARATE query rather than a join: a
            # month with lines but no Stripe row is the normal state before the billing run, and
            # an outer join would invite a reader to treat a missing row as an error.
            # Billing.Stripe_Invoice.Status is refreshed from Stripe by billing_run, so this is
            # reported state, not a guess -- and the Stripe invoice id is never sent to the
            # browser, since it is of no use to a practice and is internal plumbing.
            cur.execute(
                f"SELECT Year_Month, Status FROM Billing.Stripe_Invoice "
                f"WHERE Tenant_ID IN ({ph})", tids)
            for ym, status in cur.fetchall():
                if ym in by_month:
                    st = (status or '').lower()
                    by_month[ym]['status'] = st or None
                    by_month[ym]['status_label'] = _INVOICE_STATUS_LABEL.get(st)
            months = [by_month[y] for y in order]
        conn.close()
        return jsonify({'months': months})
    except Exception as e:
        return _server_error(e, 'get_invoices')


# ── Stripe: the payment rail ─────────────────────────────────────────────────
# SQL is the system of record for what is owed. Billing.usp_Generate_Invoice_Lines computes the
# per-seat lines (date-ranged prices, pro-rated first month, trial as the Access_From->Paid_From
# gap, affiliate commission); Stripe only collects them. So there is deliberately NO Stripe
# Subscription or Price object here -- a Customer holds the practice's card and each month's
# lines are pushed as invoice items. Two engines computing the same number is how billing
# systems silently diverge.
#
# Prices in Billing.Profile_Pricing are VAT-INCLUSIVE (full 60.00, clinician 24.00, front_office
# 6.00 -- what the practice PAYS). Dental treatment is a VAT-exempt supply, so most practices
# cannot reclaim the VAT we charge: the gross figure is a real cost to them and quoting it is the
# honest price. Billing.Invoice_Line.Value therefore holds GROSS too.
#
# So the Stripe tax rate MUST be INCLUSIVE -- Stripe derives the VAT from the gross rather than
# adding 20% on top. An exclusive rate against these figures would bill 72.00 for a full seat, and
# a tax rate's `inclusive` flag cannot be edited after creation.
#
# Keys live in Key Vault as stripe-secret-key-<env> -- never an env var, so a key cannot leak
# through a container spec or a workflow log. Same isolation as Xero.
#
# DECIDED POLICY, for the monthly charge job to implement (2026-09-17):
#   * Cards: replace-only while a practice is being billed. Removal is allowed only when there is
#     nothing to charge -- trial, free-forever, or a cancelled subscription that has ended. See
#     /api/stripe/remove-card.
#   * Cancellation detaches the card AFTER the final invoice settles, not when the button is
#     pressed: Cancelled_At is the start of next month, so billing runs to month end and that last
#     invoice still needs a card.
#   * Repeated payment failures EMAIL Sales@ and do nothing else. No automatic suspension of
#     access -- at this scale a human makes the call, because cutting off a practice over a failed
#     card is not a decision to automate while there are few enough customers to phone. Revisit
#     when the volume makes that impractical.
#   * STRIPE emails the practice about a failed payment (its own dunning emails are enabled in the
#     dashboard). So the charge job must NOT email the customer as well -- it alerts Sales@ ONLY.
#     Two "your payment failed" emails in different voices, one of them ours and one Stripe's,
#     reads as a system in disarray to the person least able to tell them apart.

STRIPE_ENV = APP_ENV if APP_ENV in ('dev', 'prod') else 'prod'
_stripe_singleton = None


def _stripe_key_prefixes():
    """Acceptable key prefixes for this environment: secret OR restricted, live XOR test.

    Restricted keys (rk_) are preferred in prod -- scoped to the handful of resources the app
    touches, so a leak cannot refund or drain the account. What must never cross is live/test.
    """
    return ('sk_live_', 'rk_live_') if STRIPE_ENV == 'prod' else ('sk_test_', 'rk_test_')


def _stripe():
    """Configured Stripe client, or raise.

    The key-prefix check is the guard that stops a non-prod deployment ever touching real
    money. dev must hold sk_test_, prod must hold sk_live_, and a mismatch fails closed --
    loudly -- rather than quietly charging real cards from dev, or quietly failing to charge
    anyone in prod because a test key was pasted into the wrong secret.
    """
    global _stripe_singleton
    if _stripe_singleton is None:
        import stripe as _s
        name = 'stripe-secret-key-' + STRIPE_ENV
        key  = (_kv_get(name) or '').strip()
        if not key:
            raise RuntimeError(name + ' is not set in Key Vault')
        # The live/test half is what must match the environment; sk_ vs rk_ is not our business.
        # A RESTRICTED key (rk_) is the right thing in prod -- it cannot issue refunds or read the
        # whole account -- and an earlier version of this check rejected exactly that.
        expected = _stripe_key_prefixes()
        if not key.startswith(expected):
            raise RuntimeError(name + ' does not start with one of ' + str(expected) +
                               ' -- refusing to use it in ' + STRIPE_ENV)
        _s.api_key = key
        _stripe_singleton = _s
    return _stripe_singleton


def _stripe_configured():
    """Is Stripe usable in this environment? True only if a correctly-prefixed key is present.

    Lets an environment run with Stripe simply absent rather than broken. Without this, prod
    shows an "Add a card" button that 500s the moment the billing owner presses it, because
    _stripe() raises on the missing secret -- a control that exists but cannot work is worse than
    one that is not offered yet.

    Never raises, and cheap after the first call: _kv_get swallows its own failures and the
    client is cached once built.
    """
    try:
        key = (_kv_get('stripe-secret-key-' + STRIPE_ENV) or '').strip()
        return key.startswith(_stripe_key_prefixes())
    except Exception:
        return False


def _lead_account_error(upn, tids, acur, action='manage billing'):
    """None if this caller may act as the practice's billing owner, else an error response.

    One definition, used by both /api/cancel and the Stripe endpoints, so the two can never
    drift on who is allowed to commit or end the practice's money.

    Deliberately refuses when no primary has been recorded rather than falling back to "any
    admin": a blank billing contact must not become a loophole. Our own support logins bypass
    it entirely -- they are never the recorded primary (the primary is picked by radio from the
    Dentally roster and a support account has no Dentally user), yet support has to be able to
    act on the practice's behalf over the phone.
    """
    if (upn or '').lower().endswith('@analytically.info'):
        return None
    acur.execute("SELECT Primary_Email FROM Input.Billing_Contact "
                 "WHERE Tenant_ID IN (" + ','.join(['?'] * len(tids)) + ")", tids)
    primaries = [(r[0] or '').strip().lower() for r in acur.fetchall() if (r[0] or '').strip()]
    if not primaries:
        return jsonify({'error': 'No primary account holder is set. Set one on the Subscriptions '
                                 'tab first — only the primary account can ' + action + '.'}), 403
    if (upn or '').lower() not in primaries:
        return jsonify({'error': 'Only the primary account holder can ' + action + '.'}), 403
    return None


def _tenant_invoice_email(tenant_id):
    """Where this practice's INVOICES should go: Invoice_Email if set, else Primary_Email.

    Deliberately NOT _tenant_primary_email, which uses the opposite precedence. That one answers
    "who is the main account holder" and feeds the monitor and token alerts, where the primary is
    the right person. For billing, an explicitly-entered Invoice_Email is a request to send
    invoices somewhere else -- usually a practice's accounts mailbox -- and must win.
    """
    try:
        conn = _appdb_conn()
        cur  = conn.cursor()
        cur.execute("SELECT TOP 1 Invoice_Email, Primary_Email FROM Input.Billing_Contact "
                    "WHERE Tenant_ID = ?", tenant_id)
        row = cur.fetchone()
        conn.close()
        return ((row[0] or row[1] or '').strip() or None) if row else None
    except Exception as e:
        app.logger.warning("invoice-email lookup failed for tenant %s: %s", tenant_id, e)
        return None


def _stripe_sync_customer_contact(cur, tenant_id):
    """Push the practice's current name + invoice address onto its Stripe Customer.

    Stripe emails receipts and hosted invoices to the Customer's own email, which is set once at
    creation -- so without this, changing the invoice contact in Settings updates our records and
    leaves Stripe billing the old address. Silent, and only discovered when someone says they
    never got an invoice.

    No-op when the tenant has no Stripe Customer yet. Never raises: a failure here must not lose
    the billing-contact save the user actually asked for.
    """
    try:
        cur.execute("SELECT Stripe_Customer_ID FROM Billing.Account_Billing WHERE Tenant_ID = ?", tenant_id)
        row = cur.fetchone()
        cust_id = (row[0] or '').strip() if row else ''
        if not cust_id:
            return False
        email = _tenant_invoice_email(tenant_id)
        cur.execute("SELECT TOP 1 Tenant_Name FROM Audit.Tenants WHERE Tenant_ID = ?", tenant_id)
        r = cur.fetchone()
        fields = {'name': (r[0] if r else None) or ('Tenant ' + str(tenant_id))}
        if email:
            fields['email'] = email
        _stripe().Customer.modify(cust_id, **fields)
        app.logger.info("stripe: synced contact for tenant %s -> %s", tenant_id, email)
        return True
    except Exception as e:
        app.logger.warning("stripe: could not sync contact for tenant %s: %s", tenant_id, e)
        return False


def _stripe_customer(cur, tenant_id):
    """This tenant's Stripe Customer id, created on first use and stored on Account_Billing.

    Carries metadata.tenant_id so anyone looking at a payment in the Stripe dashboard can get
    back to the practice without a lookup table -- which matters during a billing query.
    """
    cur.execute("SELECT Stripe_Customer_ID FROM Billing.Account_Billing WHERE Tenant_ID = ?", tenant_id)
    row = cur.fetchone()
    if row and (row[0] or '').strip():
        return (row[0] or '').strip()

    cur.execute("SELECT TOP 1 Tenant_Name FROM Audit.Tenants WHERE Tenant_ID = ?", tenant_id)
    r = cur.fetchone()
    name = (r[0] if r else None) or ('Tenant ' + str(tenant_id))

    cust = _stripe().Customer.create(
        name=name,
        email=_tenant_invoice_email(tenant_id) or None,
        metadata={'tenant_id': str(tenant_id), 'app_env': APP_ENV},
        idempotency_key='customer-' + STRIPE_ENV + '-' + str(tenant_id),
    )
    # The row normally exists already (provisioning writes it); UPDATE-then-INSERT keeps this
    # correct if billing is ever set up before Account_Billing is seeded.
    cur.execute("UPDATE Billing.Account_Billing SET Stripe_Customer_ID = ?, Updated_At = SYSUTCDATETIME() "
                "WHERE Tenant_ID = ?", cust.id, tenant_id)
    if cur.rowcount == 0:
        cur.execute("INSERT INTO Billing.Account_Billing (Tenant_ID, Stripe_Customer_ID, Updated_At) "
                    "VALUES (?, ?, SYSUTCDATETIME())", tenant_id, cust.id)
    app.logger.info("stripe: created customer %s for tenant %s", cust.id, tenant_id)
    return cust.id


def _stripe_card(cust_id):
    """The card we would charge, as a dict for the UI, or None.

    Checkout in setup mode ATTACHES the PaymentMethod to the Customer but does NOT set
    invoice_settings.default_payment_method -- so a customer can have a perfectly good card and
    still be unchargeable. Reading only the default is how "Card saved." and "No card on file."
    end up on screen together, and how a monthly invoice would later find nothing to bill.

    So: prefer the default, and if there is none but a card is attached, adopt the newest as the
    default. That self-heals the case where the browser never made it back from Checkout.
    """
    st   = _stripe()
    cust = st.Customer.retrieve(cust_id, expand=['invoice_settings.default_payment_method'])
    inv  = getattr(cust, 'invoice_settings', None)
    pm   = getattr(inv, 'default_payment_method', None)
    if pm is None:
        cards = st.PaymentMethod.list(customer=cust_id, type='card').data   # newest first
        if not cards:
            return None
        pm = cards[0]
        st.Customer.modify(cust_id, invoice_settings={'default_payment_method': pm.id})
        app.logger.info("stripe: adopted %s as default card for %s", pm.id, cust_id)
    card = getattr(pm, 'card', None)
    return {'brand': getattr(card, 'brand', None), 'last4': getattr(card, 'last4', None),
            'exp_month': getattr(card, 'exp_month', None), 'exp_year': getattr(card, 'exp_year', None)}


@app.route('/api/stripe/setup-complete', methods=['POST'])
def stripe_setup_complete():
    """Called when the browser returns from Checkout. Makes the card just entered the one we bill.

    Needed because setup-mode Checkout only attaches the card. Without this, "Change card" would
    attach a second card and keep charging the old one -- the failure nobody notices until a
    cancelled card declines.

    ONE CARD ON FILE is the rule: the newest becomes the default and any others are detached, so
    "Change card" means what it says and there is no ambiguity about what gets charged.
    Idempotent -- running it again with nothing new attached changes nothing.
    """
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn(autocommit=True)
        cur  = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        if client_id is None or not tids:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403

        ac = _appdb_conn(autocommit=True); acur = ac.cursor()
        try:
            gate = _lead_account_error(upn, tids, acur)
        finally:
            ac.close()
        if gate:
            conn.close(); return gate

        cur.execute("SELECT Stripe_Customer_ID FROM Billing.Account_Billing WHERE Tenant_ID = ?", tids[0])
        row = cur.fetchone()
        conn.close()
        cust_id = (row[0] or '').strip() if row else ''
        if not cust_id:
            return jsonify({'has_card': False})

        st    = _stripe()
        cards = st.PaymentMethod.list(customer=cust_id, type='card').data   # newest first
        if not cards:
            return jsonify({'has_card': False})
        keep = cards[0]
        st.Customer.modify(cust_id, invoice_settings={'default_payment_method': keep.id})
        for old_pm in cards[1:]:
            try:
                st.PaymentMethod.detach(old_pm.id)
            except Exception:
                app.logger.warning("stripe: could not detach superseded card %s", old_pm.id)
        app.logger.info("stripe: default card %s for tenant %s (%d superseded)",
                        keep.id, tids[0], len(cards) - 1)
        c = getattr(keep, 'card', None)
        return jsonify({'has_card': True, 'brand': getattr(c, 'brand', None),
                        'last4': getattr(c, 'last4', None),
                        'exp_month': getattr(c, 'exp_month', None),
                        'exp_year': getattr(c, 'exp_year', None)})
    except Exception as e:
        return _server_error(e, 'stripe_setup_complete')


@app.route('/api/stripe/payment-method', methods=['GET'])
def stripe_payment_method():
    """What card, if any, is on file for this practice. Drives the subscribe page's billing panel.

    Read-only, so any practice admin may see it -- knowing whether billing is set up is not the
    same as being able to change it. Never returns a card number: Stripe only ever hands back
    brand/last4/expiry, which is all the UI needs.
    """
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn(autocommit=True)
        cur  = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        if client_id is None or not tids:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403
        cur.execute("SELECT Stripe_Customer_ID FROM Billing.Account_Billing WHERE Tenant_ID = ?", tids[0])
        row = cur.fetchone()
        conn.close()

        # With no Stripe key in this environment there is nothing to show and nothing to do, so
        # report it plainly instead of offering a control that cannot work.
        if not _stripe_configured():
            return jsonify({'has_card': False, 'can_manage': False, 'configured': False})

        # Whether the caller may ADD or CHANGE the card is decided here, not in the browser. The
        # UI must never re-derive it from a roster: an account added straight to Application_Users
        # by SQL has no Dentally user, so a client-side test hides the control from precisely the
        # person who needs it. Same helper as the gate on the write endpoint.
        ac = _appdb_conn(autocommit=True); acur = ac.cursor()
        try:
            can_manage = _lead_account_error(upn, tids, acur) is None
        finally:
            ac.close()

        cust_id = (row[0] or '').strip() if row else ''
        if not cust_id:
            return jsonify({'has_card': False, 'can_manage': can_manage})

        # Stripe resources are NOT dicts in stripe>=15: .get() raises AttributeError rather than
        # returning None, so _stripe_card walks them with getattr.
        card = _stripe_card(cust_id)
        if not card:
            return jsonify({'has_card': False, 'can_manage': can_manage})
        return jsonify(dict(card, has_card=True, can_manage=can_manage))
    except Exception as e:
        return _server_error(e, 'stripe_payment_method')


@app.route('/api/stripe/setup-session', methods=['POST'])
def stripe_setup_session():
    """Start Stripe Checkout so the billing owner can save a card. Returns a URL to redirect to.

    SETUP mode, not payment or subscription mode: nothing is charged here and no subscription is
    created. The card is stored against the Customer, and the monthly job then charges the
    invoice the SQL engine produced. This keeps the amount owed in one place, and means changing
    a card never disturbs billing.

    Lead-account gated: saving a card commits the practice to being charged, so it is the
    billing owner's call rather than any admin's -- the same gate as ending the subscription.
    """
    upn, err = _auth()
    if err:
        return err
    if not _stripe_configured():
        return jsonify({'error': 'Card payments are not configured in this environment '
                                 'yet.'}), 503
    try:
        conn = _fabric_conn(autocommit=True)
        cur  = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        if client_id is None or not tids:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403

        ac = _appdb_conn(autocommit=True); acur = ac.cursor()
        try:
            gate = _lead_account_error(upn, tids, acur)
        finally:
            ac.close()
        if gate:
            conn.close(); return gate

        cust_id = _stripe_customer(cur, tids[0])
        conn.close()

        base = os.environ.get('APP_URL', 'https://app.analytically.info').rstrip('/')
        sess = _stripe().checkout.Session.create(
            mode='setup',
            customer=cust_id,
            currency='gbp',
            # Deep-link back to the tab they started from. Landing on the app home page leaves
            # them to find their own way back to see whether it worked. ?settings= is the
            # existing deep-link the alert emails use; the page strips ?billing= after reading it.
            success_url=base + '/?settings=invoices&billing=saved',
            cancel_url=base + '/?settings=invoices&billing=cancelled',
            metadata={'tenant_id': str(tids[0]), 'upn': upn},
        )
        app.logger.info("stripe: setup session %s for tenant %s by %r", sess.id, tids[0], upn)
        return jsonify({'url': sess.url})
    except Exception as e:
        return _server_error(e, 'stripe_setup_session')


@app.route('/api/stripe/remove-card', methods=['POST'])
def stripe_remove_card():
    """Remove the card on file. REFUSES while the practice is actively being billed.

    Policy (decided 2026-09-17): replace-only while active. A practice that is being charged
    cannot delete its last card, because the next invoice would have nothing to pay it -- the
    account would look fine and silently stop paying. "I want my card removed" while active is
    really "I want to stop subscribing", so the refusal points at that instead.

    The control EXISTS and explains itself rather than being hidden: someone looking for it
    should find an answer, not an absence. Removal IS allowed when there is nothing to bill --
    during a trial, on a free-forever account, or once a cancelled subscription has actually
    ended. Cancelling also detaches the card automatically after the final invoice settles, so
    the normal route needs no button at all.

    Note the final invoice is why cancelling does not detach immediately: Cancelled_At is the
    START OF NEXT MONTH, so billing runs to month end and that last invoice still needs a card.
    """
    upn, err = _auth()
    if err:
        return err
    if not _stripe_configured():
        return jsonify({'error': 'Card payments are not configured in this environment '
                                 'yet.'}), 503
    try:
        conn = _fabric_conn(autocommit=True)
        cur  = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        if client_id is None or not tids:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403

        ac = _appdb_conn(autocommit=True); acur = ac.cursor()
        try:
            gate = _lead_account_error(upn, tids, acur, action='manage billing')
        finally:
            ac.close()
        if gate:
            conn.close(); return gate

        cur.execute("SELECT Stripe_Customer_ID, Paid_From, Cancelled_At "
                    "FROM Billing.Account_Billing WHERE Tenant_ID = ?", tids[0])
        row = cur.fetchone()
        conn.close()
        if not row or not (row[0] or '').strip():
            return jsonify({'ok': True, 'has_card': False})   # nothing to remove
        cust_id, paid_from, cancelled_at = (row[0] or '').strip(), row[1], row[2]

        # Paid_From NULL means "bill from first access" (no trial), so NULL counts as billing.
        today       = datetime.utcnow().date()
        not_charging = paid_from is not None and paid_from > today
        ended        = cancelled_at is not None and cancelled_at.date() <= today
        if not (not_charging or ended):
            return jsonify({'error': 'Your subscription is active, so the card on file cannot be '
                                     'removed — the next invoice would have nothing to pay it. '
                                     'Use "Change card" to replace it, or end the subscription, '
                                     'which removes the card once the final invoice is settled.'}), 409

        st    = _stripe()
        cards = st.PaymentMethod.list(customer=cust_id, type='card').data
        for pm in cards:
            try:
                st.PaymentMethod.detach(pm.id)
            except Exception:
                app.logger.warning("stripe: could not detach %s for tenant %s", pm.id, tids[0])
        st.Customer.modify(cust_id, invoice_settings={'default_payment_method': ''})
        app.logger.info("stripe: removed %d card(s) for tenant %s by %r", len(cards), tids[0], upn)
        return jsonify({'ok': True, 'has_card': False, 'removed': len(cards)})
    except Exception as e:
        return _server_error(e, 'stripe_remove_card')


@app.route('/api/team', methods=['POST'])
def save_team():
    """Assign a subscription profile (+ My Data practitioner) per user. Writes Security.Application_Users
    (provisions the row: User_UPN=email, Client_ID=tenant client, preset module flags) and appends any
    profile CHANGE to Security.Access_Log. Never touches the caller's own row (self = full access)."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            conn.close(); return jsonify({'error': 'Only a practice admin can manage the team'}), 403
        allowed = set(tids)
        ph = ','.join(['?'] * len(tids)) if tids else 'NULL'
        cur.execute(f"SELECT Tenant_ID, Client_ID FROM Audit.Tenants WHERE Tenant_ID IN ({ph})", tids)
        client_by_tenant = {r[0]: r[1] for r in cur.fetchall()}
        # Deduce each user's My Data practitioner from their OWN linked record -- no prompt. Kept as a
        # separate stored field so it can be overridden in SQL for impersonation testing.
        cur.execute(
            f"SELECT LOWER(u.Email), MAX(dp.Full_Name) FROM Gold.Dim_Users u "
            f"JOIN Gold.Dim_Practitioners dp ON dp.Tenant_ID = u.Tenant_ID AND dp.User_ID = u.bk_User_ID AND dp.pk_Practitioner > 0 "
            f"WHERE u.Tenant_ID IN ({ph}) AND u.Is_Current = 1 GROUP BY LOWER(u.Email)", tids)
        deduced_prac = {r[0]: r[1] for r in cur.fetchall()}
        conn.close()
        # Write to AppDB (fast OLTP). Meta.usp_Sync_Input_From_AppDB upserts it into the warehouse,
        # which auth reads -- so access lands after the async sync (the UI warns "up to 10 minutes").
        payload = request.get_json(force=True) or {}
        rows = payload if isinstance(payload, list) else (payload.get('rows') or [])
        n = len(_ALL_MODULE_COLS)
        ac = _appdb_conn(autocommit=True); acur = ac.cursor()
        acur.execute("SELECT LOWER(User_UPN), " + ", ".join(_ALL_MODULE_COLS) + " FROM Input.Application_Users")
        cur_profile = {r[0]: _derive_profile({_ALL_MODULE_COLS[i] for i in range(n) if r[1 + i]})
                       for r in acur.fetchall()}
        for r in rows:
            try:
                tid = int(r['tenant_id'])
            except (KeyError, TypeError, ValueError):
                continue
            email   = (r.get('email') or '').strip()
            profile = (r.get('profile') or 'no_access').strip()
            if tid not in allowed or not email or profile not in _PROFILES:
                continue
            if email.lower() == (upn or '').lower():
                continue  # never change your own row
            cid = client_by_tenant.get(tid)
            if cid is None:
                continue
            preset  = _PROFILES[profile]
            flags   = [1 if col in preset['modules'] else 0 for col in _ALL_MODULE_COLS]
            prac    = deduced_prac.get(email.lower()) if 'Access_My_Data' in preset['modules'] else None
            admin   = 1 if r.get('admin') else 0   # Admin (Settings tab) is a per-user flag now, decoupled from the profile
            acur.execute("DELETE FROM Input.Application_Users WHERE LOWER(User_UPN) = LOWER(?)", email)
            acur.execute(
                "INSERT INTO Input.Application_Users (User_UPN, Client_ID, Display_Name, Maintain_Targets, "
                + ", ".join(_ALL_MODULE_COLS) + ", Practitioner_Full_Name, Profile_Key, Updated_By) VALUES (?, ?, ?, ?, "
                + ", ".join(['?'] * n) + ", ?, ?, ?)",
                [email, cid, (r.get('name') or email), admin] + flags + [prac, profile, upn])
            if cur_profile.get(email.lower()) != profile:
                acur.execute(
                    "INSERT INTO Input.Access_Log (Tenant_ID, User_UPN, Profile_Key, Changed_By) VALUES (?, ?, ?, ?)",
                    [tid, email, profile, upn])
        # Billing contact (primary account + invoice email), per tenant -- only when the client sent it.
        #
        # ANY practice admin may set the primary, including to themselves. That is deliberate: the
        # primary is the only account that can end the subscription, so if that person is off sick,
        # leaves, or dies, another admin has to be able to take the account over without waiting on
        # support. Restricting the change to the current primary would deadlock exactly that case
        # (and would deadlock a tenant that has no primary recorded at all, which is dev today).
        #
        # The safeguard is therefore accountability, not prevention: a takeover is announced to the
        # person losing it and to Sales@, so it can never happen quietly. Updated_By records who did
        # it. Without this, an admin could self-appoint and immediately terminate unnoticed.
        if isinstance(payload, dict) and ('primary_email' in payload or 'invoice_email' in payload):
            primary_email = (payload.get('primary_email') or '').strip() or None
            invoice_email = (payload.get('invoice_email') or '').strip() or None
            takeovers = []
            for tid in allowed:
                acur.execute("SELECT Primary_Email FROM Input.Billing_Contact WHERE Tenant_ID = ?", tid)
                prev_row  = acur.fetchone()
                prev      = ((prev_row[0] if prev_row else None) or '').strip()
                acur.execute("DELETE FROM Input.Billing_Contact WHERE Tenant_ID = ?", tid)
                acur.execute("INSERT INTO Input.Billing_Contact (Tenant_ID, Primary_Email, Invoice_Email, Updated_By) VALUES (?, ?, ?, ?)",
                             [tid, primary_email, invoice_email, upn])
                # Only a genuine handover of an EXISTING primary is announced. First-time setup has
                # nobody to tell, and re-saving the same address is not a change.
                if prev and (primary_email or '').lower() != prev.lower():
                    takeovers.append((tid, prev, primary_email))
                # Keep Stripe's copy in step, or invoices keep going to the old address.
                _stripe_sync_customer_contact(cur, tid)
            for tid, prev, now_primary in takeovers:
                _notify_primary_change(tid, prev, now_primary, upn)
        ac.close()
        return jsonify({'ok': True})
    except Exception as e:
        return _server_error(e, 'save_team')


def _notify_primary_change(tenant_id, previous, now_primary, changed_by):
    """Announce a change of primary account holder to the OUTGOING primary and to Sales@.

    The primary is the only account that can end the subscription, so handing that role over is a
    privilege change, not a preference. Any admin is allowed to do it (see save_team for why), which
    makes telling people the only thing standing between a legitimate handover and a quiet takeover.
    Best-effort -- the change is already saved and must not be rolled back by a mail failure.
    """
    body = (
        f"The primary account holder for your Analytically subscription has been changed.\n\n"
        f"  Practice tenant : {tenant_id}\n"
        f"  Was             : {previous}\n"
        f"  Now             : {now_primary or '(none)'}\n"
        f"  Changed by      : {changed_by}\n"
        f"  When            : {datetime.utcnow().strftime('%Y-%m-%d %H:%M')} UTC\n\n"
        "The primary account holder receives invoices and is the only person who can end the "
        "subscription.\n\n"
        f"If you did not expect this, reply to this email or contact {SUPPORT_FROM} straight away.\n"
    )
    # ONLY the outgoing primary is told. They are the person losing the role, so telling them is
    # the whole control -- a takeover cannot be silent. Sales@ was copied here originally and it was
    # just noise: a practice moving its own billing contact is their internal admin, and Updated_By
    # already records who did it. Sales@ IS still alerted on an actual termination, which is the
    # event that matters commercially.
    try:
        # _send_email tags and redirects non-prod centrally -- nothing to do here.
        # Reply-To is support, not the sales default: an unexpected handover is a support matter,
        # so "reply to this email" has to reach someone who can actually undo it.
        _send_email(previous, "Analytically: primary account holder changed", body,
                    reply_to=SUPPORT_FROM)
    except Exception as e:
        app.logger.warning("primary-change notice to %s failed (tenant %s): %s", previous, tenant_id, e)


def _termination_email_body(practice, tids, upn, reason, revoked):
    """Internal alert to Sales@ so a human can start the re-engagement call. Deletion is NOT
    automatic -- support runs Audit.usp_Delete_All_Tenant by hand once the account is written off."""
    return (
        f"A practice has stopped using Analytically.\n\n"
        f"  Practice   : {practice or '(unknown)'}\n"
        f"  Tenant ID  : {', '.join(str(t) for t in tids)}\n"
        f"  Ended by   : {upn}\n"
        f"  When       : {datetime.utcnow().strftime('%Y-%m-%d %H:%M')} UTC\n"
        f"  Reason     : {reason or '(none given)'}\n"
        f"  Users cut  : {revoked}\n\n"
        "Done automatically:\n"
        "  * every user set to No Access\n"
        "  * tenant deactivated (Audit.Tenants.Is_Active = 0) -- ingest stops\n"
        "  * billed to the end of the current month, nothing after\n\n"
        "NOT done -- for support to action:\n"
        "  * no data has been deleted. Re-engage first; if the account is written off, run\n"
        "    Audit.usp_Delete_All_Tenant by hand (Delete_By on Billing.Account_Billing is the\n"
        "    28-day marker shown to the customer, not a scheduled job).\n"
        "  * to reinstate: flip Is_Active back to 1 and re-grant profiles on the Subscriptions\n"
        "    tab. The ETL resumes from where it left off with a larger delta load.\n"
    )


@app.route('/api/cancel', methods=['POST'])
def cancel_subscription():
    """"Stop using Analytically": end the practice's subscription.

    LEAD ACCOUNT ONLY -- the caller must be the recorded primary on Input.Billing_Contact. Being a
    practice admin is not enough: this ends access for everyone, so it is the billing owner's call.

    What it does, all reversible:
      * every user on the tenant -> profile no_access (row KEPT, flags zeroed) + an Access_Log entry
      * Audit.Tenants.Is_Active = 0, so ingest stops and every user also fails closed in
        _get_user_info even before the AppDB->warehouse sync catches up
      * Billing.Account_Billing gets the reason, the 28-day Delete_By marker, and Cancelled_At
      * emails Sales@ so support can try to re-engage

    NOTHING is deleted here. Delete_By is a marker for the support team, who run
    Audit.usp_Delete_All_Tenant by hand -- no job consumes it.

    Two billing subtleties, both load-bearing:
      * the rows must SURVIVE. usp_Generate_Invoice_Lines draws its user list from
        Security.Application_Users and the profile history from Access_Log, so deleting the rows
        would lose the final month's invoice entirely. Hence no_access rather than DELETE.
      * Cancelled_At is set to the START OF NEXT MONTH, not now. The sproc bills a month only when
        `Cancelled_At IS NULL OR Cancelled_At > @MEnd`, so stamping it with now() would drop the
        current month -- the opposite of "billing continues to the end of the month".
    """
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn(autocommit=True)
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None or not tids:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403
        practice = None
        cur.execute("SELECT TOP 1 Tenant_Name FROM Audit.Tenants WHERE Tenant_ID = ?", tids[0])
        row = cur.fetchone()
        if row:
            practice = row[0]
        cur.execute(f"SELECT Tenant_ID, Client_ID FROM Audit.Tenants "
                    f"WHERE Tenant_ID IN ({','.join(['?'] * len(tids))})", tids)
        client_by_tenant = {r[0]: r[1] for r in cur.fetchall()}
    except Exception as e:
        return _server_error(e, 'cancel')

    # ── lead-account gate ────────────────────────────────────────────────────
    # Deliberately refuses when no primary has been recorded rather than falling back to "any
    # admin": a blank billing contact must not become a loophole that lets any admin end the
    # practice's subscription. The message says how to clear it.
    # _lead_account_error holds the only copy of this rule -- shared with the Stripe endpoints so
    # the two can never drift on who may commit or end the practice's money. is_support is still
    # needed below: support keeps its access through termination, so it is excluded from the
    # revocation sweep as well as from this gate.
    try:
        ac = _appdb_conn(autocommit=True); acur = ac.cursor()
        gate = _lead_account_error(upn, tids, acur, action='end the subscription')
    except Exception as e:
        return _server_error(e, 'cancel')
    is_support = (upn or '').lower().endswith('@analytically.info')
    if gate:
        ac.close(); conn.close()
        return gate

    reason = ((request.get_json(silent=True) or {}).get('reason') or '')[:1000]
    try:
        revoked = 0
        for tid in tids:
            cid = client_by_tenant.get(tid)
            if cid is not None:
                # Read the roster BEFORE zeroing it, so Access_Log records who actually changed.
                # Our own support logins are left alone. They are not the practice's users: they
                # are added straight to Application_Users by SQL (they have no Dentally user, so
                # they never appear on the subscriptions roster), they are already excluded from
                # billing by usp_Generate_Invoice_Lines on the same test, and support needs to keep
                # access to run the re-engagement and the eventual manual cleanup. Revoking them
                # would lock the vendor out of a tenant that still has data to deal with.
                _SUPPORT = "LOWER(User_UPN) NOT LIKE '%@analytically.info'"
                acur.execute("SELECT User_UPN FROM Input.Application_Users "
                             "WHERE Client_ID = ? AND ISNULL(Profile_Key, '') <> 'no_access' "
                             "AND " + _SUPPORT, cid)
                losing = [r[0] for r in acur.fetchall()]
                acur.execute(
                    "UPDATE Input.Application_Users SET "
                    + " = 0, ".join(_ALL_MODULE_COLS) + " = 0, "
                    + "Maintain_Targets = 0, Profile_Key = 'no_access', Practitioner_Full_Name = NULL, "
                      "Updated_By = ? WHERE Client_ID = ? AND " + _SUPPORT, [upn, cid])
                for who in losing:
                    acur.execute("INSERT INTO Input.Access_Log (Tenant_ID, User_UPN, Profile_Key, Changed_By) "
                                 "VALUES (?, ?, 'no_access', ?)", [tid, who, upn])
                revoked += len(losing)

            cur.execute("UPDATE Audit.Tenants SET Is_Active = 0 WHERE Tenant_ID = ?", tid)
            # Start of next month: keeps the current month billable, stops everything after it.
            nxt = "DATEADD(month, 1, DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1))"
            cur.execute("SELECT COUNT(*) FROM Billing.Account_Billing WHERE Tenant_ID = ?", tid)
            if cur.fetchone()[0]:
                cur.execute(f"UPDATE Billing.Account_Billing SET Cancelled_At = {nxt}, Cancel_Reason = ?, "
                            f"Delete_By = DATEADD(day, 28, CAST(SYSUTCDATETIME() AS DATE)) WHERE Tenant_ID = ?",
                            [reason, tid])
            else:
                cur.execute(f"INSERT INTO Billing.Account_Billing (Tenant_ID, Cancelled_At, Cancel_Reason, Delete_By) "
                            f"VALUES (?, {nxt}, ?, DATEADD(day, 28, CAST(SYSUTCDATETIME() AS DATE)))", [tid, reason])
        ac.close()
        conn.close()
        app.logger.warning("SUBSCRIPTION ENDED: tenant(s)=%s by=%s users_revoked=%d reason=%r",
                           tids, upn, revoked, reason)
        # Best-effort: the termination is already committed, so a mail failure must not 500 the
        # caller into thinking it did not happen. (Non-prod tagging/redirect is done centrally.)
        try:
            _send_email('Sales@Analytically.info',
                        f"Subscription ended: {practice or tids[0]}",
                        _termination_email_body(practice, tids, upn, reason, revoked))
        except Exception as e:
            app.logger.warning("termination alert email failed for tenant(s)=%s: %s", tids, e)
        return jsonify({'ok': True, 'users_revoked': revoked})
    except Exception as e:
        return _server_error(e, 'cancel')


# ── Target model: owner-curated Inputs in the AppDB Fabric SQL Database ────────
# Reads join the warehouse (practitioner list / metric catalogue) with the AppDB overrides;
# writes go to AppDB (fast OLTP). All gated on Maintain_Targets.

@app.route('/api/roles', methods=['GET'])
def get_roles():
    """Active practitioners + their current Modified Role (AppDB override, else the Dentally role)
    + the distinct role set (the target-grid columns), for the role-assignment screen."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            conn.close(); return jsonify({'error': 'Only a practice admin can manage roles'}), 403
        practitioners = []
        if tids:
            ph = ','.join(['?'] * len(tids))
            cur.execute(
                f"SELECT Tenant_ID, Practitioner_ID, Full_Name, Role "
                f"FROM Gold.Dim_Practitioners "
                f"WHERE Tenant_ID IN ({ph}) AND Active = 1 AND pk_Practitioner > 0 "
                f"ORDER BY Full_Name",
                tids,
            )
            practitioners = [
                {'tenant_id': r[0], 'practitioner_id': r[1], 'name': r[2],
                 'dentally_role': r[3], 'custom_role': r[3], 'fte': None}
                for r in cur.fetchall()
            ]
        tenants = []
        if tids:
            ph = ','.join(['?'] * len(tids))
            cur.execute(f"SELECT Tenant_ID, Tenant_Name FROM Audit.Tenants WHERE Tenant_ID IN ({ph}) AND Is_Active = 1", tids)
            tenants = [{'id': r[0], 'name': r[1]} for r in cur.fetchall()]
        dentally_roles = {p['dentally_role'] for p in practitioners if p['dentally_role']}
        conn.close()
        # AppDB: overlay overrides + read the curated role list.
        role_set = set()
        if tids:
            ac = _appdb_conn(); acur = ac.cursor(); ph = ','.join(['?'] * len(tids))
            acur.execute(f"SELECT Tenant_ID, Practitioner_ID, Custom_Role, FTE FROM Input.Practitioner_Role WHERE Tenant_ID IN ({ph})", tids)
            overrides = {(r[0], r[1]): (r[2], r[3]) for r in acur.fetchall()}
            acur.execute(f"SELECT Role_Name FROM Input.Roles WHERE Tenant_ID IN ({ph})", tids)
            role_set = {r[0] for r in acur.fetchall()}
            ac.close()
            for p in practitioners:
                ov = overrides.get((p['tenant_id'], p['practitioner_id']))
                if ov:
                    if ov[0]:            p['custom_role'] = ov[0]
                    if ov[1] is not None: p['fte'] = float(ov[1])
        # Canonical list = curated roles + any role actually IN USE (an unused/removed role does NOT
        # reappear via the Dentally defaults). dentally_roles kept only to bootstrap an empty list.
        in_use = {p['custom_role'] for p in practitioners if p['custom_role']}
        role_set |= in_use
        if not role_set:
            role_set = dentally_roles
        roles = sorted(r for r in role_set if r)
        return jsonify({'practitioners': practitioners, 'roles': roles,
                        'in_use': sorted(r for r in in_use if r), 'tenants': tenants})
    except Exception as e:
        return _server_error(e, 'get_roles')


@app.route('/api/roles', methods=['POST'])
def save_roles():
    """Upsert practitioner -> Custom_Role overrides into AppDB.Input.Practitioner_Role (SCD-1)."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        conn.close()
        if client_id is None:
            return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            return jsonify({'error': 'Only a practice admin can manage roles'}), 403
        body    = request.get_json(force=True) or {}
        allowed = set(tids)
        # practitioner assignments
        valid = []
        for r in (body.get('assignments') or []):
            try:
                tid = int(r['tenant_id']); pid = int(r['practitioner_id'])
            except (KeyError, TypeError, ValueError):
                continue
            role = (r.get('custom_role') or '').strip()
            fte = r.get('fte'); ftef = None
            if fte not in (None, ''):
                try:
                    ftef = float(fte)
                except (TypeError, ValueError):
                    ftef = None
                else:
                    if not (0 <= ftef <= 2):
                        ftef = None
            if tid in allowed and role:
                valid.append((tid, pid, role, ftef))
        # curated role list (per the primary tenant)
        try:
            rtid = int(body.get('tenant_id'))
        except (TypeError, ValueError):
            rtid = None
        role_names = sorted({str(x).strip() for x in (body.get('roles') or []) if str(x).strip()})

        ac = _appdb_conn(autocommit=True); acur = ac.cursor()
        if valid:
            acur.fast_executemany = True
            acur.executemany(
                "DELETE FROM Input.Practitioner_Role WHERE Tenant_ID = ? AND Practitioner_ID = ?",
                [(t, p) for t, p, _, _ in valid])
            acur.executemany(
                "INSERT INTO Input.Practitioner_Role (Tenant_ID, Practitioner_ID, Custom_Role, FTE, Updated_At, Updated_By) "
                "VALUES (?, ?, ?, ?, SYSUTCDATETIME(), ?)",
                [(t, p, role, fte, upn) for t, p, role, fte in valid])
        if rtid in allowed:
            acur.execute("DELETE FROM Input.Roles WHERE Tenant_ID = ?", rtid)
            if role_names:
                acur.fast_executemany = True
                acur.executemany(
                    "INSERT INTO Input.Roles (Tenant_ID, Role_Name, Updated_At, Updated_By) VALUES (?, ?, SYSUTCDATETIME(), ?)",
                    [(rtid, n, upn) for n in role_names])
        ac.close()
        return jsonify({'ok': True})
    except Exception as e:
        return _server_error(e, 'save_roles')


@app.route('/api/variances', methods=['GET'])
def get_variances():
    """Active metrics + their current per-metric tolerance band (AppDB override, else null)."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            conn.close(); return jsonify({'error': 'Only a practice admin can manage variances'}), 403
        cur.execute(
            "SELECT Metric_Key, Display_Name, Section, Format_Type, Range_Type, Long_Description "
            "FROM Config.Metric_Definitions WHERE Is_Active = 1 AND ISNULL(Has_Target, 1) = 1 "
            "ORDER BY Display_Order")
        metrics = [{'key': r[0], 'display_name': r[1], 'section': r[2],
                    'format_type': r[3], 'range_type': r[4], 'definition': r[5]} for r in cur.fetchall()]
        tenants = []
        if tids:
            ph = ','.join(['?'] * len(tids))
            cur.execute(f"SELECT Tenant_ID, Tenant_Name FROM Audit.Tenants WHERE Tenant_ID IN ({ph}) AND Is_Active = 1", tids)
            tenants = [{'id': r[0], 'name': r[1]} for r in cur.fetchall()]
        conn.close()
        variances = {}
        if tids:
            ac = _appdb_conn(); acur = ac.cursor()
            ph = ','.join(['?'] * len(tids))
            acur.execute(
                f"SELECT Tenant_ID, Metric, Variance FROM Input.Metric_Variance WHERE Tenant_ID IN ({ph})", tids)
            for r in acur.fetchall():
                variances[f"{r[0]}|{r[1]}"] = float(r[2]) if r[2] is not None else None
            ac.close()
        return jsonify({'metrics': metrics, 'variances': variances, 'tenants': tenants})
    except Exception as e:
        return _server_error(e, 'get_variances')


@app.route('/api/variances', methods=['POST'])
def save_variances():
    """Upsert per-metric variance bands into AppDB.Input.Metric_Variance. Blank/null clears (DELETE only)."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        conn.close()
        if client_id is None:
            return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            return jsonify({'error': 'Only a practice admin can manage variances'}), 403
        rows    = request.get_json(force=True) or []
        allowed = set(tids)
        valid   = []
        for r in rows:
            try:
                tid = int(r['tenant_id'])
            except (KeyError, TypeError, ValueError):
                continue
            metric = str(r.get('metric') or '').strip()
            if tid not in allowed or not metric:
                continue
            v = r.get('variance')
            valid.append((tid, metric, float(v) if v not in (None, '') else None))
        if valid:
            ac = _appdb_conn(autocommit=True); acur = ac.cursor(); acur.fast_executemany = True
            acur.executemany(
                "DELETE FROM Input.Metric_Variance WHERE Tenant_ID = ? AND Metric = ?",
                [(t, m) for t, m, _ in valid])
            inserts = [(t, m, v) for t, m, v in valid if v is not None]
            if inserts:
                acur.executemany(
                    "INSERT INTO Input.Metric_Variance (Tenant_ID, Metric, Variance, Updated_At, Updated_By) "
                    "VALUES (?, ?, ?, SYSUTCDATETIME(), ?)",
                    [(t, m, v, upn) for t, m, v in inserts])
            ac.close()
        return jsonify({'ok': True})
    except Exception as e:
        return _server_error(e, 'save_variances')


@app.route('/api/plan-capitation', methods=['GET'])
def get_plan_capitation():
    """Catalogue of ALL in-use payment plans (>=1 active member) with member counts + the owner's saved
    effective-dated rates / default flag (AppDB). Owner-only. We do NOT guess which plans are capitation
    -- naming varies by practice (Denplan/Den/Tabeo/Patient Plan/...) -- so the whole list is shown and
    the owner enters rates only against the capitation ones. Plans left with no rate (Private, NHS, ...)
    generate no records. The rate drives Fact_Plan_Capitation."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            conn.close(); return jsonify({'error': 'Only a practice admin can manage plan rates'}), 403
        plans = []
        if tids:
            ph = ','.join(['?'] * len(tids))
            cur.execute(
                f"SELECT pp.Tenant_ID, pp.Payment_Plan_ID, pp.Payment_Plan_Name, pp.Standard_Payment_Plan, "
                f"       ISNULL(ac.cnt, 0) AS current_patients "
                f"FROM Gold.Dim_Payment_Plans pp "
                f"LEFT JOIN (SELECT Tenant_ID, Payment_Plan_ID, COUNT(*) cnt FROM Gold.Dim_Patients "
                f"           WHERE Active = 1 GROUP BY Tenant_ID, Payment_Plan_ID) ac "
                f"       ON ac.Tenant_ID = pp.Tenant_ID AND ac.Payment_Plan_ID = pp.Payment_Plan_ID "
                f"WHERE pp.Tenant_ID IN ({ph}) "
                f"  AND NULLIF(LTRIM(RTRIM(pp.Payment_Plan_Name)),'') IS NOT NULL "
                f"  AND ISNULL(ac.cnt, 0) > 0 "
                f"ORDER BY pp.Payment_Plan_Name", tids)
            plans = [{'tenant_id': r[0], 'payment_plan_id': r[1], 'name': r[2], 'standard_plan': r[3],
                      'current_patients': r[4], 'is_default': False, 'rates': []} for r in cur.fetchall()]
        conn.close()
        if tids and plans:
            ac = _appdb_conn(); acur = ac.cursor(); ph = ','.join(['?'] * len(tids))
            acur.execute(f"SELECT Tenant_ID, Payment_Plan_ID, Monthly_Value, Effective_From_Date, Is_Default "
                         f"FROM Input.Plan_Capitation_Rate WHERE Tenant_ID IN ({ph}) "
                         f"ORDER BY Effective_From_Date", tids)
            by_plan, defaults = {}, set()
            for r in acur.fetchall():
                by_plan.setdefault((r[0], r[1]), []).append(
                    {'effective_from': r[3].isoformat() if r[3] else None, 'monthly_value': float(r[2])})
                if r[4]:
                    defaults.add((r[0], r[1]))
            ac.close()
            for p in plans:
                key = (p['tenant_id'], p['payment_plan_id'])
                p['rates']      = by_plan.get(key, [])
                p['is_default'] = key in defaults
        return jsonify({'plans': plans})
    except Exception as e:
        return _server_error(e, 'get_plan_capitation')


@app.route('/api/plan-capitation', methods=['POST'])
def save_plan_capitation():
    """Replace the tenant's plan capitation rates in AppDB.Input.Plan_Capitation_Rate. Each plan can
    carry MANY effective-dated (Effective_From_Date, Monthly_Value) rows -- the fee-over-time history.
    Blank/zero value or blank date skips that row. `default_plan_id` flags every row of the one plan
    that values lapsed members. Duplicate dates within a plan are de-duped (last wins)."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn(); cur = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        conn.close()
        if client_id is None:
            return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            return jsonify({'error': 'Only a practice admin can manage plan rates'}), 403
        body    = request.get_json(force=True) or {}
        allowed = set(tids)
        rows    = body.get('rates') or []
        try:
            default_pid = int(body.get('default_plan_id'))
        except (TypeError, ValueError):
            default_pid = None
        seen         = {}   # (tid, pid, eff) -> (tid, pid, eff, value, is_default)  [de-dupe by date]
        payload_tids = set()
        for r in rows:
            try:
                tid = int(r['tenant_id']); pid = int(r['payment_plan_id'])
            except (KeyError, TypeError, ValueError):
                continue
            if tid not in allowed:
                continue
            payload_tids.add(tid)
            mv  = r.get('monthly_value')
            eff = str(r.get('effective_from') or '').strip()
            if mv in (None, '') or not eff:
                continue  # a row needs BOTH a date and a value
            try:
                mvf = float(mv)
            except (TypeError, ValueError):
                continue
            if mvf <= 0:
                continue
            seen[(tid, pid, eff)] = (tid, pid, eff, mvf, 1 if pid == default_pid else 0)
        valid = list(seen.values())
        ac = _appdb_conn(autocommit=True); acur = ac.cursor()
        for t in payload_tids:
            acur.execute("DELETE FROM Input.Plan_Capitation_Rate WHERE Tenant_ID = ?", t)
        if valid:
            acur.fast_executemany = True
            acur.executemany(
                "INSERT INTO Input.Plan_Capitation_Rate (Tenant_ID, Payment_Plan_ID, Effective_From_Date, "
                "Monthly_Value, Is_Default, Updated_At, Updated_By) VALUES (?, ?, ?, ?, ?, SYSUTCDATETIME(), ?)",
                [(t, p, e, m, d, upn) for t, p, e, m, d in valid])
        ac.close()
        return jsonify({'ok': True})
    except Exception as e:
        return _server_error(e, 'save_plan_capitation')


@app.route('/api/target-grid', methods=['GET'])
def get_target_grid():
    """The target grid for an FY: metric catalogue (with definition, per-metric sample and the
    FTE_Scaled flag) x (Practice + roles), current target values + per-metric variance (AppDB)."""
    upn, err = _auth()
    if err:
        return err
    try:
        import datetime
        fy = int(request.args.get('fy') or 0)
        if not fy:
            t = datetime.date.today()
            fy = t.year if t.month >= 4 else t.year - 1
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            conn.close(); return jsonify({'error': 'Only a practice admin can manage targets'}), 403

        # Year picker = the practice FYs from the cutover to the current FY (same as the app's period
        # FYs, from Gold.Dim_Date_Grouping) PLUS next year, so targets can be set historically (so
        # prior-year reports have targets) and for next year. FY label year = 2000 + the FYyy digits.
        # Resilient: a warehouse not yet on the tenant-FY grouping (no Tenant_ID column) falls back to
        # an empty range + the existing Apr-Mar default, so the Targets screen never 500s.
        fy_options = []
        if tids:
            _ph = ','.join(['?'] * len(tids))
            try:
                cur.execute(f"SELECT DISTINCT Date_Grouping FROM Gold.Dim_Date_Grouping WHERE Tenant_ID IN ({_ph})", tids)
                _yrs = [2000 + int(v[2:]) for (v,) in cur.fetchall() if v and v.startswith('FY') and v[2:].isdigit()]
                if _yrs:
                    fy_options = list(range(min(_yrs), max(_yrs) + 2))   # cutover .. current + 1 (next year)
            except Exception:
                fy_options = []
        if fy_options and not request.args.get('fy'):
            fy = max(fy_options) - 1       # default to the practice current FY (overrides the Apr-Mar guess)

        cur.execute(
            "SELECT Metric_Key, Display_Name, Section, Format_Type, Range_Type, Target_Type, "
            "ISNULL(Supports_Practitioner, 0), Long_Description, Sample_Value, ISNULL(FTE_Scaled, 0) "
            "FROM Config.Metric_Definitions WHERE Is_Active = 1 AND ISNULL(Has_Target, 1) = 1 "
            "ORDER BY Display_Order")
        metrics = [{'key': r[0], 'display_name': r[1], 'section': r[2], 'format_type': r[3],
                    'range_type': r[4], 'target_type': r[5], 'splits_by_role': bool(r[6]),
                    'definition': r[7], 'sample': r[8], 'fte_scaled': bool(r[9])}
                   for r in cur.fetchall()]

        tenants, roles_by_tenant, prac_roles = {}, {}, {}
        if tids:
            ph = ','.join(['?'] * len(tids))
            cur.execute(f"SELECT Tenant_ID, Tenant_Name FROM Audit.Tenants WHERE Tenant_ID IN ({ph}) AND Is_Active = 1", tids)
            tenants = {r[0]: {'id': r[0], 'name': r[1], 'levels': ['Practice'],
                              'targets': {}, 'variances': {}} for r in cur.fetchall()}
            # Base = Dentally role per active practitioner; overlaid below with the LIVE AppDB override
            # (same as the Roles screen) so reassigned/removed roles show immediately, not after the
            # nightly Dim_Practitioners.Custom_Role refresh.
            cur.execute(
                f"SELECT Tenant_ID, Practitioner_ID, Role FROM Gold.Dim_Practitioners "
                f"WHERE Tenant_ID IN ({ph}) AND Active = 1 AND pk_Practitioner > 0", tids)
            prac_roles = {(r[0], r[1]): r[2] for r in cur.fetchall()}
        conn.close()

        available_fys = []
        if tids:
            ac = _appdb_conn(); acur = ac.cursor(); ph = ','.join(['?'] * len(tids))
            acur.execute(
                f"SELECT Tenant_ID, Metric, Target_Level, Target_Value FROM Input.Targets "
                f"WHERE Tenant_ID IN ({ph}) AND FY = ?", tids + [fy])
            for r in acur.fetchall():
                if r[0] in tenants:
                    tenants[r[0]]['targets'][f"{r[1]}|{r[2]}"] = float(r[3])
            acur.execute(f"SELECT Tenant_ID, Metric, Variance FROM Input.Metric_Variance WHERE Tenant_ID IN ({ph})", tids)
            for r in acur.fetchall():
                if r[0] in tenants:
                    tenants[r[0]]['variances'][r[1]] = float(r[2]) if r[2] is not None else None
            acur.execute(f"SELECT DISTINCT FY FROM Input.Targets WHERE Tenant_ID IN ({ph}) ORDER BY FY", tids)
            available_fys = [r[0] for r in acur.fetchall()]
            # Overlay the live per-practitioner role override, then the effective in-use roles become columns.
            acur.execute(f"SELECT Tenant_ID, Practitioner_ID, Custom_Role FROM Input.Practitioner_Role WHERE Tenant_ID IN ({ph})", tids)
            for r in acur.fetchall():
                if (r[0], r[1]) in prac_roles and r[2]:
                    prac_roles[(r[0], r[1])] = r[2]
            for (tid_, pid_), role_ in prac_roles.items():
                if role_:
                    roles_by_tenant.setdefault(tid_, set()).add(role_)
            acur.execute(f"SELECT Tenant_ID, Role_Name FROM Input.Roles WHERE Tenant_ID IN ({ph})", tids)
            for r in acur.fetchall():
                roles_by_tenant.setdefault(r[0], set()).add(r[1])
            ac.close()

        for tid, t in tenants.items():
            t['levels'] = ['Practice'] + sorted(roles_by_tenant.get(tid, set()))

        return jsonify({'fy': fy, 'available_fys': available_fys, 'fy_options': fy_options,
                        'metrics': metrics, 'tenants': list(tenants.values())})
    except Exception as e:
        return _server_error(e, 'get_target_grid')


@app.route('/api/target-grid', methods=['POST'])
def save_target_grid():
    """Upsert target-grid cells into AppDB.Input.Targets for one FY. Blank value clears (DELETE only).
    Body: {fy, rows:[{tenant_id, metric, target_level, value}]}."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        conn.close()
        if client_id is None:
            return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            return jsonify({'error': 'Only a practice admin can manage targets'}), 403
        body = request.get_json(force=True) or {}
        try:
            fy = int(body.get('fy'))
        except (TypeError, ValueError):
            return jsonify({'error': 'fy required'}), 400
        allowed = set(tids)
        valid   = []
        for r in (body.get('rows') or []):
            try:
                tid = int(r['tenant_id'])
            except (KeyError, TypeError, ValueError):
                continue
            metric = str(r.get('metric') or '').strip()
            level  = str(r.get('target_level') or '').strip()
            if tid not in allowed or not metric or not level:
                continue
            v = r.get('value')
            valid.append((tid, metric, level, float(v) if v not in (None, '') else None))
        if valid:
            ac = _appdb_conn(autocommit=True); acur = ac.cursor(); acur.fast_executemany = True
            acur.executemany(
                "DELETE FROM Input.Targets WHERE Tenant_ID = ? AND FY = ? AND Metric = ? AND Target_Level = ?",
                [(t, fy, m, l) for t, m, l, _ in valid])
            inserts = [(t, fy, m, l, v, upn) for t, m, l, v in valid if v is not None]
            if inserts:
                acur.executemany(
                    "INSERT INTO Input.Targets (Tenant_ID, FY, Metric, Target_Level, Target_Value, Updated_At, Updated_By) "
                    "VALUES (?, ?, ?, ?, ?, SYSUTCDATETIME(), ?)", inserts)
            ac.close()
        return jsonify({'ok': True})
    except Exception as e:
        return _server_error(e, 'save_target_grid')


# ── Admin: the billing console (our own staff only) ──────────────────────────
# Everything the monthly run does, in one screen, for the practice the picker has selected: what
# Stripe actually thinks, what we think, the lines, a manual correction to any of them, a credit
# note, and the corrected re-issue.
#
# It acts on the CURRENT practice and takes no tenant argument of its own. The picker has already
# moved the whole app (see _acting_client_id), so the Admin screen resolves identity exactly like
# every other route and cannot reach a practice the caller is not looking at.
#
# The logic is billing_run's, imported rather than reimplemented. Two engines deciding what a
# practice owes is how billing systems silently diverge, and a console that disagreed with the
# command line would be worse than no console.

def _require_staff():
    """(upn, None) for our own logins; (None, 403) for anyone else.

    Enforced on every admin route rather than inferred from the UI hiding the tab. The tab being
    invisible is a convenience; this is the control.
    """
    upn, err = _auth()
    if err:
        return None, err
    if not _is_staff(upn):
        return None, (jsonify({'error': 'Forbidden'}), 403)
    return upn, None


def _billing():
    """billing_run, imported lazily.

    At module scope this would make the whole app fail to start if a billing dependency were
    missing -- reports would go down over a screen almost nobody opens.
    """
    import billing_run
    return billing_run


def _admin_tenant(cur, upn, body_tenant=None):
    """The tenant this admin action applies to, or (None, error).

    Resolved from the CALLER's current practice and then checked against the id the browser sent,
    so a stale tab that still names the previous practice is refused rather than silently acting on
    the one now selected.
    """
    _, client_id, tids, _ = _get_user_info(cur, upn)
    if client_id is None or not tids:
        return None, (jsonify({'error': 'Forbidden'}), 403)
    if body_tenant is None:
        # ==> DO NOT GUESS WHICH PRACTICE AN ADMIN WRITE LANDS ON. <== This returned tids[0],
        # which was unambiguous only because no client had ever had more than one tenant.
        # V186's junction makes that false -- the Analytically client sees every practice --
        # and an arbitrary "first" tenant is the wrong thing to be arbitrary about: it is an
        # admin action, writing, to whichever tenant the query happened to return first.
        if len(tids) > 1:
            return None, (jsonify({'error': 'Select a practice first.'}), 409)
        return tids[0], None
    try:
        tid = int(body_tenant)
    except (TypeError, ValueError):
        return None, (jsonify({'error': 'Bad tenant'}), 400)
    if tid not in tids:
        return None, (jsonify({'error': 'That practice is no longer the one selected. '
                                        'Reload and try again.'}), 409)
    return tid, None


def _admin_ym(default_last=True):
    v = (request.args.get('year_month') or (request.get_json(silent=True) or {}).get('year_month'))
    if v in (None, ''):
        return _billing().last_month() if default_last else None
    try:
        ym = int(v)
    except (TypeError, ValueError):
        return None
    return ym if 190001 <= ym <= 299912 and 1 <= ym % 100 <= 12 else None


@app.route('/api/admin/billing', methods=['GET'])
def admin_billing():
    """Everything known about one practice-month: our lines, our adjustments, and Stripe's view.

    Stripe is re-read live rather than reported from Billing.Stripe_Invoice. Our Status is stale the
    moment a human finalises an invoice in the dashboard, and the whole point of this screen is to
    show the position before someone acts on it.
    """
    upn, err = _require_staff()
    if err:
        return err
    ym = _admin_ym()
    if ym is None:
        return jsonify({'error': 'Bad month'}), 400
    try:
        br   = _billing()
        conn = _fabric_conn()
        cur  = conn.cursor()
        tid, terr = _admin_tenant(cur, upn)
        if terr:
            conn.close(); return terr

        cur.execute("SELECT Tenant_Name FROM Audit.Tenants WHERE Tenant_ID = ?", tid)
        r = cur.fetchone()
        name = (r[0] if r else None) or f'Tenant {tid}'

        # Months worth offering: anything with lines, an invoice, or an adjustment.
        cur.execute(
            "SELECT DISTINCT Year_Month FROM ("
            "  SELECT Year_Month FROM Billing.Invoice_Line WHERE Tenant_ID = ?"
            "  UNION ALL SELECT Year_Month FROM Billing.Stripe_Invoice WHERE Tenant_ID = ?"
            "  UNION ALL SELECT Year_Month FROM Billing.Credit_Note WHERE Tenant_ID = ?"
            "  UNION ALL SELECT Year_Month FROM Billing.Invoice_Line_Adjustment WHERE Tenant_ID = ?"
            ") m ORDER BY Year_Month DESC", tid, tid, tid, tid)
        months = [r[0] for r in cur.fetchall()]
        if ym not in months:
            months = sorted(set(months) | {ym}, reverse=True)

        cur.execute(
            "SELECT User_UPN, Display_Name, Profile_Key, Value FROM Billing.Invoice_Line "
            "WHERE Tenant_ID = ? AND Year_Month = ? ORDER BY Value DESC, Display_Name", tid, ym)
        lines = [{'upn': a, 'name': b or a, 'profile': c,
                  'profile_label': br.PROFILE_LABEL.get(c, c), 'value': float(d or 0)}
                 for a, b, c, d in cur.fetchall()]

        cur.execute(
            "SELECT User_UPN, Action, Override_Value, Reason, Created_At, Created_By "
            "FROM Billing.Invoice_Line_Adjustment WHERE Tenant_ID = ? AND Year_Month = ?", tid, ym)
        adj = {(a or '').lower(): {'action': b, 'value': float(c) if c is not None else None,
                                   'reason': d, 'at': e.isoformat() if e else None, 'by': f}
               for a, b, c, d, e, f in cur.fetchall()}
        for l in lines:
            l['adjustment'] = adj.get(l['upn'].lower())
        # An adjustment can name someone who no longer produces a line at all -- an excluded user,
        # most obviously. Show them, or the screen would offer no way to undo the exclusion.
        for upn_k, a in adj.items():
            if not any(l['upn'].lower() == upn_k for l in lines):
                lines.append({'upn': upn_k, 'name': upn_k, 'profile': None, 'profile_label': '—',
                              'value': 0.0, 'adjustment': a, 'suppressed': True})

        cur.execute("SELECT Stripe_Invoice_ID, Stripe_Customer_ID, Status, Amount_Pence, Line_Count "
                    "FROM Billing.Stripe_Invoice WHERE Tenant_ID = ? AND Year_Month = ?", tid, ym)
        r = cur.fetchone()
        ours = {'invoice_id': r[0], 'customer': r[1], 'status': r[2],
                'amount': (r[3] or 0) / 100, 'line_count': r[4]} if r else None

        cur.execute(
            "SELECT Stripe_Credit_Note_ID, Credit_Note_Number, Stripe_Invoice_ID, Amount_Pence, "
            " Tax_Pence, Refund_Pence, Credit_Balance_Pence, Reason, Memo, Created_At, Created_By "
            "FROM Billing.Credit_Note WHERE Tenant_ID = ? AND Year_Month = ? ORDER BY Created_At",
            tid, ym)
        credits = [{'id': a, 'number': b, 'invoice_id': c, 'amount': (d or 0) / 100,
                    'tax': (e or 0) / 100, 'refund': (f or 0) / 100 if f else None,
                    'balance': (g or 0) / 100 if g else None, 'reason': h, 'memo': i,
                    'at': j.isoformat() if j else None, 'by': k}
                   for a, b, c, d, e, f, g, h, i, j, k in cur.fetchall()]

        cur.execute("SELECT Stripe_Customer_ID, Paid_From, Cancelled_At FROM Billing.Account_Billing "
                    "WHERE Tenant_ID = ?", tid)
        r = cur.fetchone()
        customer  = (r[0] or '').strip() if r else ''
        cancelled = r[2] if r else None
        conn.close()

        # Stripe's own view. Never fatal: the screen is still useful with our side alone, and an
        # outage here must not hide the lines or the audit trail.
        stripe_view, has_card, err_msg = None, None, None
        try:
            st = _stripe()
            if ours and ours['invoice_id']:
                inv = st.Invoice.retrieve(ours['invoice_id'])
                d   = inv.to_dict()
                stripe_view = {
                    'invoice_id': inv.id, 'number': d.get('number'), 'status': inv.status,
                    'status_label': _INVOICE_STATUS_LABEL.get((inv.status or '').lower()),
                    'total': (d.get('total') or 0) / 100,
                    'tax': br.invoice_tax_pence(inv) / 100,
                    'credited': br.credited_pence(inv) / 100,
                    'amount_paid': (d.get('amount_paid') or 0) / 100,
                    'hosted_url': d.get('hosted_invoice_url'),
                    'agrees': bool(ours) and (d.get('total') or 0) == round(ours['amount'] * 100),
                }
            if customer:
                c = st.Customer.retrieve(customer, expand=['invoice_settings.default_payment_method'])
                has_card = getattr(getattr(c, 'invoice_settings', None),
                                   'default_payment_method', None) is not None
        except Exception as e:
            app.logger.warning('admin_billing: Stripe unreadable: %s', e)
            err_msg = 'Stripe could not be read just now. The figures below are ours, not theirs.'

        total = round(sum(l['value'] for l in lines if not l.get('suppressed')), 2)
        return jsonify({
            'tenant_id': tid, 'practice': name, 'year_month': ym, 'months': months,
            'lines': lines, 'total': total, 'ours': ours, 'stripe': stripe_view,
            'credit_notes': credits, 'customer': customer, 'has_card': has_card,
            'cancelled_at': cancelled.isoformat() if cancelled else None,
            'stripe_error': err_msg, 'env': APP_ENV,
        })
    except Exception as e:
        return _server_error(e, 'admin_billing')


class _StripeDown(Exception):
    """Stripe could not be reached or is not configured here."""


def _stripe_or_refuse():
    """Stripe, or a refusal the operator can act on.

    Every write below turns on what Stripe says, so "Stripe is unreadable" must never be answered
    with a guess. An unhandled failure here surfaced as a bare 500, which reads like a broken
    screen rather than a temporary outage and invites a retry that cannot work.
    """
    try:
        return _stripe()
    except Exception as e:
        app.logger.warning('admin: Stripe unavailable: %s', e)
        raise _StripeDown('Stripe cannot be reached right now, so I cannot tell whether that '
                          'invoice has already been issued. Nothing has been changed — try again '
                          'shortly.')


def _finalised_in_stripe(br, st, cur, tid, ym):
    """Is this month's invoice beyond a draft? Asked of STRIPE, not of our table.

    Our Status is stale from the instant someone finalises in the dashboard, and every destructive
    action below turns on this answer. Returns (status or None, invoice_id or None).
    """
    cur.execute("SELECT Stripe_Invoice_ID FROM Billing.Stripe_Invoice "
                "WHERE Tenant_ID = ? AND Year_Month = ?", tid, ym)
    r = cur.fetchone()
    if not r or not r[0]:
        return None, None
    try:
        inv = st.Invoice.retrieve(r[0])
    except Exception:
        return None, r[0]        # gone from Stripe -> treat as absent, same as the run does
    s = (inv.status or '').lower()
    return (s if s not in ('draft', '') else None), inv.id


@app.route('/api/admin/billing/adjust', methods=['POST'])
def admin_billing_adjust():
    """Record (or clear) a manual correction to one user's line, then rebuild the month.

    The rebuild is the point: an adjustment that did not show up in the figures immediately would
    leave someone guessing whether it had taken. A month holding a FINALISED invoice is NOT rebuilt
    -- those lines are the evidence of what was charged -- but the adjustment is still recorded, so
    it applies the moment the invoice is credited.
    """
    upn, err = _require_staff()
    if err:
        return err
    body   = request.get_json(silent=True) or {}
    ym     = _admin_ym()
    action = (body.get('action') or '').strip().lower()
    target = (body.get('upn') or '').strip()
    reason = (body.get('reason') or '').strip()
    if ym is None or not target or action not in ('exclude', 'override', 'clear'):
        return jsonify({'error': 'Bad request'}), 400
    value = None
    if action == 'override':
        try:
            value = round(float(body.get('value')), 2)
        except (TypeError, ValueError):
            return jsonify({'error': 'A replacement amount is required.'}), 400
        if value < 0:
            return jsonify({'error': 'A replacement amount cannot be negative.'}), 400
    if action != 'clear' and not reason:
        # It changes what a practice is charged. In six months the only account of why will be this.
        return jsonify({'error': 'Please give a reason — it is the only record of why.'}), 400
    try:
        # autocommit=True, and it MUST be. _fabric_conn defaults to a transaction and these
        # handlers close without committing, so every write here silently rolled back --
        # while the response reported success, because the endpoint read the figures back
        # inside its own uncommitted transaction. It looked like it had worked.
        conn = _fabric_conn(autocommit=True); cur = conn.cursor()
        tid, terr = _admin_tenant(cur, upn, body.get('tenant_id'))
        if terr:
            conn.close(); return terr
        cur.execute("DELETE FROM Billing.Invoice_Line_Adjustment "
                    "WHERE Tenant_ID = ? AND Year_Month = ? AND LOWER(User_UPN) = LOWER(?)",
                    tid, ym, target)
        if action != 'clear':
            cur.execute(
                "INSERT INTO Billing.Invoice_Line_Adjustment (Tenant_ID, Year_Month, User_UPN, "
                " Action, Override_Value, Reason, Created_At, Created_By) VALUES (?,?,?,?,?,?,?,?)",
                tid, ym, target, action, value, reason[:500],
                datetime.utcnow().replace(microsecond=0), upn[:255])

        st = _stripe_or_refuse()
        status, _inv = _finalised_in_stripe(_billing(), st, cur, tid, ym)
        if status:
            conn.close()
            return jsonify({'ok': True, 'regenerated': False, 'invoice_status': status,
                            'note': f'Recorded. The {ym // 100}-{ym % 100:02d} invoice is already '
                                    f'{status}, so the figures are unchanged until it is credited.'})
        cur.execute("EXEC Billing.usp_Generate_Invoice_Lines @Year_Month = ?", ym)
        cur.execute("SELECT COUNT(1), ISNULL(SUM(Value), 0) FROM Billing.Invoice_Line "
                    "WHERE Tenant_ID = ? AND Year_Month = ?", tid, ym)
        n, total = cur.fetchone()
        conn.close()
        return jsonify({'ok': True, 'regenerated': True, 'lines': n, 'total': float(total or 0)})
    except _StripeDown as e:
        return jsonify({'error': str(e)}), 503
    except Exception as e:
        return _server_error(e, 'admin_billing_adjust')


@app.route('/api/admin/billing/raise', methods=['POST'])
def admin_billing_raise():
    """Rebuild the month and raise (or re-raise) its Stripe DRAFT. Charges nothing.

    Same posture as the command line: drafts only. Finalising is what takes the money and stays a
    deliberate act in the Stripe dashboard, by a human who has read the figures.
    """
    upn, err = _require_staff()
    if err:
        return err
    ym = _admin_ym()
    if ym is None:
        return jsonify({'error': 'Bad month'}), 400
    try:
        br = _billing(); br.new_run_id()
        st = _stripe_or_refuse()
        # autocommit=True, and it MUST be. _fabric_conn defaults to a transaction and these
        # handlers close without committing, so every write here silently rolled back --
        # while the response reported success, because the endpoint read the figures back
        # inside its own uncommitted transaction. It looked like it had worked.
        conn = _fabric_conn(autocommit=True); cur = conn.cursor()
        tid, terr = _admin_tenant(cur, upn, (request.get_json(silent=True) or {}).get('tenant_id'))
        if terr:
            conn.close(); return terr

        status, inv_id = _finalised_in_stripe(br, st, cur, tid, ym)
        if status:
            conn.close()
            return jsonify({'error': f'That invoice is already {status}. Credit it first, then '
                                     f're-issue.'}), 409

        cur.execute("EXEC Billing.usp_Generate_Invoice_Lines @Year_Month = ?", ym)
        t = br.fetch_month(cur, ym).get(tid)
        if not t:
            conn.close()
            return jsonify({'error': 'Nothing to bill for that month.'}), 409

        has_card = False
        if t['customer']:
            c = st.Customer.retrieve(t['customer'], expand=['invoice_settings.default_payment_method'])
            has_card = getattr(getattr(c, 'invoice_settings', None),
                               'default_payment_method', None) is not None
        why = br.blocked_reason(t, has_card)
        if why:
            conn.close(); return jsonify({'error': f'Cannot raise it: {why}.'}), 409

        # Discard the old draft first, so the practice is never left holding two invoices for one
        # month. Invoice.delete refuses anything but a draft, which is the safety we want.
        if inv_id:
            try:
                st.Invoice.delete(inv_id)
            except Exception as e:
                conn.close()
                return jsonify({'error': f'Could not discard the previous draft: {str(e)[:160]}'}), 409
        # Belt and braces, exactly as the run does: Stripe may hold an invoice we lost the row for.
        elif br.find_in_stripe(st, t['customer'], ym) is not None:
            conn.close()
            return jsonify({'error': 'Stripe already holds an invoice for that month that we have '
                                     'no record of. Reconcile before raising another.'}), 409

        inv = br.raise_draft(st, t, ym, br.vat_rate_id(st))
        br.record(cur, t, ym, invoice=inv)
        conn.close()
        d = inv.to_dict()
        app.logger.info('admin: %s raised draft %s for tenant %s %s', upn, inv.id, tid, ym)
        return jsonify({'ok': True, 'invoice_id': inv.id, 'status': inv.status,
                        'total': (d.get('total') or 0) / 100,
                        'tax': br.invoice_tax_pence(inv) / 100,
                        'lines': len(t['lines']), 'hosted_url': d.get('hosted_invoice_url')})
    except _StripeDown as e:
        return jsonify({'error': str(e)}), 503
    except Exception as e:
        return _server_error(e, 'admin_billing_raise')


@app.route('/api/admin/billing/credit-note', methods=['POST'])
def admin_billing_credit_note():
    """Credit an ISSUED invoice in full and refund it, reopening the month for a corrected one.

    THE ONE PLACE IN THIS APP THAT RETURNS MONEY. It is billing_run.credit_note verbatim: full
    credit, line by line so the VAT mirrors the invoice, refusing a draft, a void, or anything
    already credited. The confirmation is the caller's job; the refusals are this code's.
    """
    upn, err = _require_staff()
    if err:
        return err
    body   = request.get_json(silent=True) or {}
    ym     = _admin_ym()
    reason = (body.get('reason') or 'order_change').strip()
    memo   = (body.get('memo') or '').strip()
    if ym is None:
        return jsonify({'error': 'Bad month'}), 400
    if reason not in ('duplicate', 'fraudulent', 'order_change', 'product_unsatisfactory'):
        return jsonify({'error': 'Bad reason'}), 400
    if not memo:
        memo = (f'Credit note for the Analytically subscription invoice for '
                f'{ym // 100}-{ym % 100:02d}. A corrected invoice follows.')
    try:
        br = _billing(); br.new_run_id()
        # autocommit=True, and it MUST be. _fabric_conn defaults to a transaction and these
        # handlers close without committing, so every write here silently rolled back --
        # while the response reported success, because the endpoint read the figures back
        # inside its own uncommitted transaction. It looked like it had worked.
        conn = _fabric_conn(autocommit=True); cur = conn.cursor()
        tid, terr = _admin_tenant(cur, upn, body.get('tenant_id'))
        if terr:
            conn.close(); return terr
        out = _capture(br.credit_note, _stripe_or_refuse(), cur, tid, ym, reason, memo,
                       to_balance=bool(body.get('to_balance')))
        conn.close()
        issued, text = out
        app.logger.info('admin: %s credit-note tenant %s %s -> issued=%s', upn, tid, ym, issued)
        return jsonify({'ok': bool(issued), 'issued': bool(issued), 'detail': text})
    except _StripeDown as e:
        return jsonify({'error': str(e)}), 503
    except Exception as e:
        return _server_error(e, 'admin_billing_credit_note')


@app.route('/api/admin/affiliate', methods=['GET'])
def admin_affiliate():
    """Who introduced the selected practice, and every affiliate we already know about.

    The affiliate list comes back whole so the screen can offer the ones already on the books.
    The common case is a partner who has introduced several practices, and retyping their email
    is exactly how you end up with two affiliate records and half the commission going to each.
    """
    upn, err = _require_staff()
    if err:
        return err
    try:
        conn = _fabric_conn(); cur = conn.cursor()
        tid, terr = _admin_tenant(cur, upn)
        if terr:
            conn.close(); return terr
        cur.execute(
            "SELECT ab.Affiliate_ID, af.Email, af.Name, af.Commission_Pct, "
            "       ab.Affiliate_Commission_Pct "
            "FROM Billing.Account_Billing ab "
            "LEFT JOIN Billing.Affiliate af ON af.Affiliate_ID = ab.Affiliate_ID "
            "WHERE ab.Tenant_ID = ?", tid)
        row = cur.fetchone()
        current = None
        if row and row[0] is not None:
            # Standard rate AND override are both returned so it is obvious WHICH is in force.
            # A screen showing only the effective number makes an override invisible until it
            # surprises someone.
            current = {'affiliate_id': row[0], 'email': row[1], 'name': row[2],
                       'standard_pct': float(row[3]) * 100 if row[3] is not None else None,
                       'override_pct': float(row[4]) * 100 if row[4] is not None else None,
                       'effective_pct': float(row[4] if row[4] is not None else (row[3] or 0)) * 100}
        cur.execute("SELECT Affiliate_ID, Email, Name, Commission_Pct FROM Billing.Affiliate "
                    "ORDER BY Email")
        known = [{'affiliate_id': r[0], 'email': r[1], 'name': r[2],
                  'pct': float(r[3]) * 100 if r[3] is not None else None} for r in cur.fetchall()]
        conn.close()
        return jsonify({'tenant_id': tid, 'current': current, 'known': known})
    except Exception as e:
        return _server_error(e, 'admin_affiliate')


@app.route('/api/admin/affiliate', methods=['POST'])
def admin_affiliate_set():
    """Link the selected practice to an affiliate by email, or unlink it.

    ==> THIS DOES NOT PAY ANYONE RETROSPECTIVELY, AND MUST NOT. <== The rate is stamped onto each
    invoice line by Billing.usp_Generate_Invoice_Lines at generation time, so this takes effect on
    the NEXT run. Months already generated keep whatever affiliate they had, which is the honest
    behaviour -- an introducer did not introduce a practice that was already billing. Unlike the
    adjust route, this deliberately does NOT regenerate the month.

    An unknown email CREATES the affiliate: that is the onboarding path, previously a hand-written
    INSERT in SSMS. A rate is required with it, because an affiliate with no rate earns nothing and
    would sit there looking linked while silently paying zero.
    """
    upn, err = _require_staff()
    if err:
        return err
    body   = request.get_json(silent=True) or {}
    action = (body.get('action') or 'set').strip().lower()
    email  = (body.get('email') or '').strip().lower()
    name   = (body.get('name') or '').strip()
    if action not in ('set', 'clear'):
        return jsonify({'error': 'Bad request'}), 400
    pct = None
    if action == 'set':
        if '@' not in email or '.' not in email.split('@')[-1]:
            return jsonify({'error': 'A valid affiliate email is required.'}), 400
        raw = body.get('commission_pct')
        if raw not in (None, ''):
            try:
                pct = round(float(raw), 3)
            except (TypeError, ValueError):
                return jsonify({'error': 'The commission rate must be a number.'}), 400
            # Entered as a PERCENTAGE. 0.1 here would mean a tenth of one percent, which nobody
            # has ever agreed to -- it means the fraction was typed instead. Refusing beats
            # silently paying an introducer a hundredth of what was agreed, for the life of the
            # account, with nothing downstream ever flagging it.
            if pct < 0.5 or pct > 100:
                return jsonify({'error': 'Enter the rate as a percentage, e.g. 10 for 10%. '
                                         'Values below 0.5 look like a fraction.'}), 400
    try:
        # autocommit=True -- see admin_billing_adjust. Without it this writes nothing and reports
        # success.
        conn = _fabric_conn(autocommit=True); cur = conn.cursor()
        tid, terr = _admin_tenant(cur, upn, body.get('tenant_id'))
        if terr:
            conn.close(); return terr

        # A practice that has never been billed has no Account_Billing row to update.
        cur.execute("SELECT COUNT(1) FROM Billing.Account_Billing WHERE Tenant_ID = ?", tid)
        if not cur.fetchone()[0]:
            cur.execute("INSERT INTO Billing.Account_Billing (Tenant_ID, Updated_At) VALUES (?,?)",
                        tid, datetime.utcnow().replace(microsecond=0))

        now = datetime.utcnow().replace(microsecond=0)
        if action == 'clear':
            cur.execute("UPDATE Billing.Account_Billing "
                        "SET Affiliate_ID = NULL, Affiliate_Commission_Pct = NULL, Updated_At = ? "
                        "WHERE Tenant_ID = ?", now, tid)
            conn.close()
            return jsonify({'ok': True, 'cleared': True,
                            'note': 'Unlinked. Invoices already generated keep the commission '
                                    'they were raised with.'})

        cur.execute("SELECT Affiliate_ID, Commission_Pct FROM Billing.Affiliate "
                    "WHERE LOWER(Email) = ?", email)
        found = cur.fetchone()
        created = False
        if found:
            aff_id, std = found[0], found[1]
            if name:
                cur.execute("UPDATE Billing.Affiliate SET Name = ? WHERE Affiliate_ID = ?",
                            name[:255], aff_id)
        else:
            if pct is None:
                conn.close()
                return jsonify({'error': email + ' is new, so a commission rate is required to '
                                                 'create them.'}), 400
            # Affiliate_ID is manually assigned by design -- a small vendor-managed set, no
            # IDENTITY on the table -- so the app takes the next one.
            cur.execute("SELECT ISNULL(MAX(Affiliate_ID), 0) + 1 FROM Billing.Affiliate")
            aff_id = cur.fetchone()[0]
            std = round(pct / 100.0, 5)
            cur.execute("INSERT INTO Billing.Affiliate (Affiliate_ID, Email, Name, Commission_Pct, "
                        " Created_At, Notes) VALUES (?,?,?,?,?,?)",
                        aff_id, email[:255], (name or None), std, now, 'Added by ' + upn[:200])
            created = True

        # A rate given for an EXISTING affiliate is a PER-TENANT OVERRIDE, never a change to their
        # standard rate: one practice on different terms must not silently re-rate every other
        # practice that partner has introduced.
        override = round(pct / 100.0, 5) if (pct is not None and not created) else None
        cur.execute("UPDATE Billing.Account_Billing "
                    "SET Affiliate_ID = ?, Affiliate_Commission_Pct = ?, Updated_At = ? "
                    "WHERE Tenant_ID = ?", aff_id, override, now, tid)
        effective = (override if override is not None else std) or 0
        conn.close()
        return jsonify({'ok': True, 'created': created, 'affiliate_id': aff_id, 'email': email,
                        'effective_pct': round(float(effective) * 100, 3),
                        'note': ('Created and linked. ' if created else 'Linked. ')
                                + 'Commission applies from the next invoice run; months already '
                                  'generated are unchanged.'})
    except Exception as e:
        return _server_error(e, 'admin_affiliate_set')


def _capture(fn, *a, **kw):
    """Run one of billing_run's functions and collect what it prints.

    Those functions report by printing -- they were written for a human reading a terminal, and the
    text is genuinely the best explanation of what happened and why something was refused. Rather
    than duplicate that reasoning in two places and let the two drift, the console shows the same
    words the command line would have.
    """
    import contextlib, io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        n = fn(*a, **kw)
    return n, buf.getvalue().strip()


if __name__ == '__main__':
    _debug = os.environ.get('FLASK_DEBUG', '').lower() in ('1', 'true', 'yes')
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=_debug)
