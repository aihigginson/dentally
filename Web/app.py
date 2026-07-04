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

# ── Public routes ─────────────────────────────────────────────────────────────

@app.route('/')
def index():
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

        role_clause  = "AND LOWER(Role) = LOWER(?) " if role_filter != 'all' else ""
        pract_params = list(tids) + ([role_filter] if role_filter != 'all' else [])
        cur.execute(
            f"SELECT Practitioner_ID, Full_Name "
            f"FROM   Gold.Dim_Practitioners "
            f"WHERE  Tenant_ID IN ({placeholders}) "
            f"AND    pk_Practitioner > 0 "
            f"{role_clause}"
            f"ORDER BY Full_Name",
            pract_params,
        )
        practitioners = [{'id': str(r[0]), 'name': r[1]} for r in cur.fetchall()]
        conn.close()
        return jsonify({'sites': sites, 'practitioners': practitioners})

    except Exception as e:
        # Preserve the 200 + empty-lists client contract; log detail server-side.
        app.logger.exception("filters failed: %s", e)
        return jsonify({'sites': [], 'practitioners': []})


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
        "WHERE LOWER(a.User_UPN) = LOWER(?)",
        upn,
    )
    tids = [r[0] for r in cur.fetchall()]
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
                f"SELECT p.Tenant_ID, p.Practitioner_ID, p.Full_Name, p.Role, pp.Associate_Pct "
                f"FROM Gold.Dim_Practitioners p "
                f"LEFT JOIN Input.Practitioner_Pay pp "
                f"  ON pp.Tenant_ID = p.Tenant_ID AND pp.Practitioner_ID = p.Practitioner_ID "
                f"WHERE p.Tenant_ID IN ({ph}) AND p.Active = 1 AND p.pk_Practitioner > 0 "
                f"ORDER BY p.Full_Name",
                tids,
            )
            practitioners = [
                {'tenant_id': r[0], 'practitioner_id': r[1], 'name': r[2], 'role': r[3],
                 'associate_pct': float(r[4]) if r[4] is not None else None}
                for r in cur.fetchall()
            ]
        conn.close()
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
        conn = _fabric_conn(autocommit=True)
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
        # (tenant_id, practitioner_id, pct-or-None), only for the caller's tenant(s).
        valid = []
        for r in rows:
            try:
                tid = int(r['tenant_id']); pid = int(r['practitioner_id'])
            except (KeyError, TypeError, ValueError):
                continue
            if tid not in allowed:
                continue
            pct = r.get('associate_pct')
            if pct in (None, ''):
                valid.append((tid, pid, None))
            else:
                try:
                    pctf = float(pct)
                except (TypeError, ValueError):
                    continue
                if 0 <= pctf <= 100:
                    valid.append((tid, pid, pctf))

        if valid:
            cur.fast_executemany = True
            cur.executemany(
                "DELETE FROM Input.Practitioner_Pay WHERE Tenant_ID = ? AND Practitioner_ID = ?",
                [(t, p) for t, p, _ in valid],
            )
            inserts = [(t, p, v) for t, p, v in valid if v is not None]
            if inserts:
                cur.executemany(
                    "INSERT INTO Input.Practitioner_Pay "
                    "(Tenant_ID, Practitioner_ID, Associate_Pct, DW_Created_At, DW_Updated_At) "
                    "VALUES (?, ?, ?, GETUTCDATE(), GETUTCDATE())",
                    inserts,
                )
        conn.close()
        return jsonify({'ok': True})
    except Exception as e:
        return _server_error(e, 'save_practitioner_pay')


if __name__ == '__main__':
    _debug = os.environ.get('FLASK_DEBUG', '').lower() in ('1', 'true', 'yes')
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=_debug)
