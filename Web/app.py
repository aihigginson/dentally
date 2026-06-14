from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
import msal
import requests
import pyodbc
import struct
import os
from dotenv import load_dotenv
import jwt
from jwt import PyJWKClient

load_dotenv()

app = Flask(__name__, static_folder='.', static_url_path='')
CORS(app)

APP_ENV        = os.environ.get('APP_ENV', 'prod')
TENANT_ID      = os.environ['TENANT_ID']
CLIENT_ID      = os.environ['CLIENT_ID']
CLIENT_SECRET  = os.environ['CLIENT_SECRET']
WORKSPACE_ID   = os.environ['WORKSPACE_ID']
DATASET_ID     = os.environ['DATASET_ID']
USERNAME       = os.environ['PBI_USERNAME']
PASSWORD       = os.environ['PBI_PASSWORD']
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
}
print("Reports loaded:", {k: (v[:8] + '...') if v else '(missing)' for k, v in REPORTS.items()})


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

# ── Service-principal helpers (PBI + Fabric) ──────────────────────────────────

def _pbi_token():
    result = msal.ConfidentialClientApplication(
        CLIENT_ID, authority=PBI_AUTHORITY, client_credential=CLIENT_SECRET,
    ).acquire_token_for_client(scopes=PBI_SCOPE)
    if 'access_token' not in result:
        raise RuntimeError(result.get('error_description', 'MSAL token acquisition failed'))
    return result['access_token']


def _pbi_delegated_token():
    result = msal.ConfidentialClientApplication(
        CLIENT_ID, authority=PBI_AUTHORITY, client_credential=CLIENT_SECRET,
    ).acquire_token_by_username_password(username=USERNAME, password=PASSWORD, scopes=PBI_SCOPE)
    if 'access_token' not in result:
        raise RuntimeError(result.get('error_description', 'MSAL delegated token acquisition failed'))
    return result['access_token']


def _fabric_access_token():
    result = msal.ConfidentialClientApplication(
        AZURE_CLIENT_ID,
        authority=f'https://login.microsoftonline.com/{TENANT_ID}',
        client_credential=AZURE_CLIENT_SECRET,
    ).acquire_token_for_client(scopes=['https://database.windows.net//.default'])
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
        print("[embed-token] REFUSED: REPORT_ROLES is empty", flush=True)
        return jsonify({'error': 'Server RLS misconfiguration'}), 500
    # 2. The caller must be a provisioned application user mapped to >= 1 tenant.
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        conn.close()
    except Exception:
        return jsonify({'error': 'Authorization check failed'}), 500
    if client_id is None or not tids:
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
        print(f"[embed-token] upn={upn!r} roles={REPORT_ROLES!r} report={report_name}", flush=True)
        r2 = requests.post(
            f'{PBI_BASE}/groups/{WORKSPACE_ID}/reports/{report_id}/GenerateToken',
            headers=headers, json=token_body, timeout=10,
        )
        r2.raise_for_status()
        return jsonify({'token': r2.json()['token'], 'embedUrl': embed_url, 'reportId': report_id})

    except requests.HTTPError as e:
        return jsonify({'error': str(e), 'detail': e.response.text}), 502
    except Exception as e:
        return jsonify({'error': str(e)}), 500


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
        conn.close()
        return jsonify({
            'display_name':     display_name or upn,
            'client_id':        client_id,
            'tenant_ids':       tids,
            'practice_name':    practice_name,
            'maintain_targets': maintain_targets,
            'env':              APP_ENV,
        })
    except Exception as e:
        import traceback
        print(f"ME ERROR: {e}\n{traceback.format_exc()}", flush=True)
        return jsonify({'error': str(e)}), 500


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
        return jsonify({'sites': [], 'practitioners': [], '_error': str(e)})


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
        return jsonify({'error': str(e)}), 500


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
        import traceback
        print(f"[save_targets] ERROR: {repr(e)}\n{traceback.format_exc()}", flush=True)
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=True)
