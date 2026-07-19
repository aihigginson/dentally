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

APP_ENV        = os.environ.get('APP_ENV', 'prod')
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
    warehouse; the SP/managed identity must be granted a user in AppDB (see AppDB/README.md)."""
    token        = _fabric_access_token()
    token_bytes  = token.encode('utf-16-le')
    token_struct = struct.pack(f'<I{len(token_bytes)}s', len(token_bytes), token_bytes)
    conn_str = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={APPDB_SERVER},1433;"
        f"Database={APPDB_DB};"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )
    return pyodbc.connect(conn_str, attrs_before={1256: token_struct}, autocommit=autocommit)

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
        token_body = {
            'accessLevel': 'View',
            'identities': [{
                'username': upn,
                'roles':    REPORT_ROLES,
                'datasets': [dataset_id],
            }],
        }
        app.logger.info("embed-token issued: upn=%r roles=%r report=%s", upn, REPORT_ROLES, report_name)
        r2 = requests.post(
            f'{PBI_BASE}/groups/{WORKSPACE_ID}/reports/{report_id}/GenerateToken',
            headers=headers, json=token_body, timeout=10,
        )
        r2.raise_for_status()
        return jsonify({'token': r2.json()['token'], 'embedUrl': embed_url, 'reportId': report_id})

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
        conn.close()
        return jsonify({'sites': sites, 'practitioners': practitioners, 'roles': roles})

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
_dentally_app_creds = {}


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


def _send_email(to, subject, body):
    """Send a transactional email. Prefers Azure Communication Services -- keyless via ACS_ENDPOINT +
    managed identity, else a connection string in Key Vault ('acs-connection-string'). Falls back to
    SMTP (ONBOARDING_SMTP_*); otherwise (dev) logs the body so the flow is testable. Returns True if sent.
    Sender must be an address on the domain connected to the ACS resource (set ONBOARDING_FROM)."""
    sender   = os.environ.get('ONBOARDING_FROM', 'DoNotReply@analytically.info')
    reply_to = os.environ.get('ONBOARDING_REPLY_TO', 'sales@analytically.info')
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
            'senderAddress': sender,
            'recipients': {'to': [{'address': to}]},
            'replyTo':     [{'address': reply_to}],
            'content':     {'subject': subject, 'plainText': body},
        }).result()
        return True
    host = os.environ.get('ONBOARDING_SMTP_HOST')
    if host:
        import smtplib
        from email.mime.text import MIMEText
        msg = MIMEText(body)
        msg['Subject'] = subject
        msg['From'] = os.environ.get('ONBOARDING_FROM', 'noreply@analytically.info')
        msg['To'] = to
        with smtplib.SMTP(host, int(os.environ.get('ONBOARDING_SMTP_PORT', '587'))) as s:
            s.starttls()
            user = os.environ.get('ONBOARDING_SMTP_USER')
            if user:
                s.login(user, os.environ.get('ONBOARDING_SMTP_PASS', ''))
            s.sendmail(msg['From'], [to], msg.as_string())
        return True
    app.logger.warning("onboarding email (NO PROVIDER configured) to=%s subject=%s :: %s", to, subject, body)
    return False


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
            pr = requests.get(DENTALLY_API_BASE + '/practices', headers={
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
            'oauth':                tokens,
        }
        _kv_set(pending_secret, json.dumps(store))
        app.logger.info("onboarding captured: practice=%s id=%s principal=%s paid_from=%s",
                        practice_name, practice_id, state['email'], paid_from)
        return redirect('/onboarding?status=connected')
    except Exception as e:
        app.logger.exception("onboarding callback failed: %s", e)
        return redirect('/onboarding?status=error')


# ── Helpers ───────────────────────────────────────────────────────────────────

def _get_user_info(cur, upn):
    """Returns (display_name, client_id, tenant_ids, maintain_targets) or (None, None, [], False)."""
    cur.execute(
        "SELECT Display_Name, Client_ID, Maintain_Targets "
        "FROM Security.Application_Users WHERE LOWER(User_UPN) = LOWER(?)",
        upn,
    )
    row = cur.fetchone()
    if not row:
        return None, None, [], False
    display_name, client_id, maintain_targets = row[0], row[1], bool(row[2])
    cur.execute(
        "SELECT t.Tenant_ID FROM Security.Application_Users a "
        "JOIN Audit.Tenants t ON a.Client_ID = t.Client_ID "
        "WHERE LOWER(a.User_UPN) = LOWER(?) AND ISNULL(t.Is_Active, 1) = 1",
        upn,
    )
    tids = [r[0] for r in cur.fetchall()]
    if not tids:
        return None, None, [], False   # no ACTIVE tenant (e.g. cancelled subscription) -> fail closed
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
    'clinician':    {'label': 'Clinician',    'modules': {'Access_Home','Access_Clinical','Access_NHS','Access_Schedule','Access_Patient','Access_My_Data'}, 'maintain_targets': False, 'desc': 'Access to the clinician’s OWN data only.'},
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
            # ACTIVE staff only. A user's active flag comes from their linked practitioner
            # (Dim_Practitioners.User_ID = Dim_Users.bk_User_ID) -- exclude users whose practitioner is
            # inactive (departed clinicians). Non-practitioners (front office) have no such flag, so are
            # kept. That same link gives the DEDUCED My Data practitioner (no prompt needed).
            # Active flag lives on the PRACTITIONER record (Dentally embeds the user inside it).
            # Silver.Practitioners keeps every staff role (front office included) -- unlike
            # Gold.Dim_Practitioners which is clinical-only -- so join it for Practitioner_Active and
            # drop anyone whose practitioner record is inactive (departed). Users with no practitioner
            # record (act NULL) are kept. Dim_Practitioners still gives the deduced My Data name.
            cur.execute(
                f"SELECT u.Tenant_ID, u.Email, u.Full_Name, u.Role, u.Site_ID, dp.practitioner "
                f"FROM Gold.Dim_Users u "
                f"LEFT JOIN (SELECT Tenant_ID, User_ID, MAX(Practitioner_Active) AS act "
                f"           FROM Silver.Practitioners GROUP BY Tenant_ID, User_ID) sp "
                f"           ON sp.Tenant_ID = u.Tenant_ID AND sp.User_ID = u.bk_User_ID "
                f"LEFT JOIN (SELECT Tenant_ID, User_ID, MAX(Full_Name) AS practitioner "
                f"           FROM Gold.Dim_Practitioners WHERE pk_Practitioner > 0 AND User_ID IS NOT NULL "
                f"           GROUP BY Tenant_ID, User_ID) dp ON dp.Tenant_ID = u.Tenant_ID AND dp.User_ID = u.bk_User_ID "
                f"WHERE u.Tenant_ID IN ({ph}) AND u.Is_Current = 1 AND NULLIF(LTRIM(RTRIM(u.Email)),'') IS NOT NULL "
                f"  AND ISNULL(sp.act, 1) = 1 "
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


@app.route('/api/invoices', methods=['GET'])
def get_invoices():
    """Billing history for the caller's practice: Billing.Invoice_Line grouped by month (each line is a
    subscribed user; the first part-month at sign-up is pro-rated). Read-only, owner-only. DEV generates
    real lines but issues no payment request; free-forever / trial months simply have no lines."""
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
                    by_month[ym] = {'year_month': ym, 'total': 0.0, 'lines': []}
                    order.append(ym)
                by_month[ym]['lines'].append({'name': name or email, 'email': email,
                                              'profile': plabels.get(pk, pk), 'value': float(val or 0)})
                by_month[ym]['total'] += float(val or 0)
            months = [by_month[y] for y in order]
        conn.close()
        return jsonify({'months': months})
    except Exception as e:
        return _server_error(e, 'get_invoices')


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
        if isinstance(payload, dict) and ('primary_email' in payload or 'invoice_email' in payload):
            primary_email = (payload.get('primary_email') or '').strip() or None
            invoice_email = (payload.get('invoice_email') or '').strip() or None
            for tid in allowed:
                acur.execute("DELETE FROM Input.Billing_Contact WHERE Tenant_ID = ?", tid)
                acur.execute("INSERT INTO Input.Billing_Contact (Tenant_ID, Primary_Email, Invoice_Email, Updated_By) VALUES (?, ?, ?, ?)",
                             [tid, primary_email, invoice_email, upn])
        ac.close()
        return jsonify({'ok': True})
    except Exception as e:
        return _server_error(e, 'save_team')


@app.route('/api/cancel', methods=['POST'])
def cancel_subscription():
    """Cancel the practice's subscription: IMMEDIATE revocation (Audit.Tenants.Is_Active=0 -> every user
    on the tenant then fails closed in _get_user_info) + record the reason and Delete_By = +28 days on
    Billing.Account_Billing. Owner-only. Data is purged by the offboarding job on/after Delete_By."""
    upn, err = _auth()
    if err:
        return err
    try:
        conn = _fabric_conn(autocommit=True)
        cur  = conn.cursor()
        _, client_id, tids, maintain = _get_user_info(cur, upn)
        if client_id is None:
            conn.close(); return jsonify({'error': 'Forbidden'}), 403
        if not maintain:
            conn.close(); return jsonify({'error': 'Only a practice admin can cancel the subscription'}), 403
        reason = ((request.get_json(silent=True) or {}).get('reason') or '')[:1000]
        for tid in tids:
            cur.execute("UPDATE Audit.Tenants SET Is_Active = 0 WHERE Tenant_ID = ?", tid)
            cur.execute("SELECT COUNT(*) FROM Billing.Account_Billing WHERE Tenant_ID = ?", tid)
            if cur.fetchone()[0]:
                cur.execute("UPDATE Billing.Account_Billing SET Cancelled_At = SYSUTCDATETIME(), Cancel_Reason = ?, "
                            "Delete_By = DATEADD(day, 28, CAST(SYSUTCDATETIME() AS DATE)) WHERE Tenant_ID = ?", [reason, tid])
            else:
                cur.execute("INSERT INTO Billing.Account_Billing (Tenant_ID, Cancelled_At, Cancel_Reason, Delete_By) "
                            "VALUES (?, SYSUTCDATETIME(), ?, DATEADD(day, 28, CAST(SYSUTCDATETIME() AS DATE)))", [tid, reason])
        conn.close()
        app.logger.info("subscription cancelled: tenant(s)=%s by=%s reason=%r", tids, upn, reason)
        return jsonify({'ok': True})
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

        return jsonify({'fy': fy, 'available_fys': available_fys,
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


if __name__ == '__main__':
    _debug = os.environ.get('FLASK_DEBUG', '').lower() in ('1', 'true', 'yes')
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=_debug)
