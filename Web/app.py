from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
import msal
import requests
import pyodbc
import os
from dotenv import load_dotenv
import jwt
from jwt import PyJWKClient

load_dotenv()

app = Flask(__name__, static_folder='.', static_url_path='')
CORS(app)

TENANT_ID      = os.environ['TENANT_ID']
CLIENT_ID      = os.environ['CLIENT_ID']
CLIENT_SECRET  = os.environ['CLIENT_SECRET']
WORKSPACE_ID   = os.environ['WORKSPACE_ID']
DATASET_ID     = os.environ['DATASET_ID']
USERNAME       = os.environ['PBI_USERNAME']
PASSWORD       = os.environ['PBI_PASSWORD']
REPORT_ROLES   = [r.strip() for r in os.environ.get('REPORT_ROLES', '').split(',') if r.strip()]
FABRIC_SERVER  = os.environ['FABRIC_SERVER']
FABRIC_DB      = os.environ.get('FABRIC_DB', 'WH_Dentally')

PBI_AUTHORITY = f'https://login.microsoftonline.com/{TENANT_ID}'
PBI_SCOPE     = ['https://analysis.windows.net/powerbi/api/.default']
PBI_BASE      = 'https://api.powerbi.com/v1.0/myorg'

REPORTS = {
    'revenue':    os.environ.get('REPORT_ID_REVENUE',   ''),
    'patients':   os.environ.get('REPORT_ID_PATIENT') or os.environ.get('REPORT_ID_PATIENTS', ''),
    'treatment':  os.environ.get('REPORT_ID_TREATMENT', ''),
    'scheduling': os.environ.get('REPORT_ID_SCHEDULE',  ''),
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


def _fabric_conn():
    conn_str = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={FABRIC_SERVER},1433;"
        f"Database={FABRIC_DB};"
        f"Authentication=ActiveDirectoryPassword;"
        f"UID={USERNAME};"
        f"PWD={PASSWORD};"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )
    return pyodbc.connect(conn_str)

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

        token_body = {'accessLevel': 'View'}
        if REPORT_ROLES:
            token_body['identities'] = [{
                'username': USERNAME,
                'roles':    REPORT_ROLES,
                'datasets': [dataset_id],
            }]
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
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/filters')
def filters():
    upn, err = _auth()
    if err:
        return err

    active_only = request.args.get('active_only', '1') == '1'
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

        active_w = "AND Active = 1" if active_only else ""
        cur.execute(
            f"SELECT Practitioner_ID, Full_Name "
            f"FROM   Gold.Dim_Practitioners "
            f"WHERE  Tenant_ID IN ({placeholders}) {active_w} "
            f"ORDER BY Full_Name",
            tids,
        )
        practitioners = [{'id': str(r[0]), 'name': r[1]} for r in cur.fetchall()]
        conn.close()
        return jsonify({'sites': sites, 'practitioners': practitioners})

    except Exception as e:
        return jsonify({'sites': [], 'practitioners': [], '_error': str(e)})


@app.route('/api/kpis')
def kpis():
    upn, err = _auth()
    if err:
        return err

    section  = request.args.get('section',  'revenue')
    period   = request.args.get('period',   'all')
    site_id  = request.args.get('site',     'all')
    pract_id = request.args.get('pract',    'all')

    dispatch = {
        'revenue':    _kpis_revenue,
        'patients':   _kpis_patients,
        'treatment':  _kpis_treatment,
        'scheduling': _kpis_scheduling,
        'nhs':        _kpis_nhs,
    }
    fn = dispatch.get(section)
    if not fn:
        return jsonify({})

    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        if client_id is None:
            conn.close()
            return jsonify({'error': 'Forbidden'}), 403
        targets     = _fetch_targets(cur, tids)
        metric_meta = _fetch_metric_meta(cur)
        result      = fn(cur, tids, period, site_id, pract_id, targets, metric_meta)
        conn.close()
        return jsonify(result)
    except Exception as e:
        return jsonify({'_error': str(e)}), 500

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
        "SELECT Tenant_ID FROM Security.User_Tenants WHERE LOWER(User_UPN) = LOWER(?)",
        upn,
    )
    tids = [r[0] for r in cur.fetchall()]
    return display_name, client_id, tids, maintain_targets


def _tid_in(tids, params, alias=None):
    """Appends tids to params; returns SQL IN fragment e.g. 'fi.Tenant_ID IN (?,?)'."""
    params.extend(tids)
    field = f"{alias}.Tenant_ID" if alias else "Tenant_ID"
    return f"{field} IN ({','.join(['?'] * len(tids))})"


def _pw(date_col, period, params):
    if period and period != 'all':
        params.append(period)
        return (f"AND {date_col} IN "
                f"(SELECT fk_Date FROM Gold.Dim_Date_Grouping WHERE Date_Grouping = ?)")
    return ""


def _sw(site_id, tids, params, alias='fi'):
    """Site filter for fact tables using fk_Practice_Site."""
    if site_id and site_id != 'all':
        ph = ','.join(['?'] * len(tids))
        params.extend([str(site_id)] + list(tids))
        return (f"AND {alias}.fk_Practice_Site IN "
                f"(SELECT pk_Practice_Site FROM Gold.Dim_Practice_Sites "
                f"WHERE Site_ID = ? AND Tenant_ID IN ({ph}))")
    return ""


def _agg_sw(site_id, tids, params, alias='d'):
    """Site filter for aggregate tables using fk_Site."""
    if site_id and site_id != 'all':
        ph = ','.join(['?'] * len(tids))
        params.extend([str(site_id)] + list(tids))
        return (f"AND {alias}.fk_Site IN "
                f"(SELECT pk_Practice_Site FROM Gold.Dim_Practice_Sites "
                f"WHERE Site_ID = ? AND Tenant_ID IN ({ph}))")
    return ""


def _prw(pract_id, tids, params, alias='fi'):
    if pract_id and pract_id != 'all':
        ph = ','.join(['?'] * len(tids))
        params.extend([str(pract_id)] + list(tids))
        return (f"AND {alias}.fk_Practitioner IN "
                f"(SELECT pk_Practitioner FROM Gold.Dim_Practitioners "
                f"WHERE CAST(Practitioner_ID AS VARCHAR) = ? AND Tenant_ID IN ({ph}))")
    return ""


def _fetch_targets(cur, tids):
    """Returns {metric_key: {tenant_id: {value, variance}}} for all user tenants."""
    if not tids:
        return {}
    ph = ','.join(['?'] * len(tids))
    cur.execute(
        f"SELECT Tenant_ID, Metric, Target_Value, Variance FROM Input.Targets "
        f"WHERE Tenant_ID IN ({ph}) AND Period_Type = 'all_time' AND Period_Value = 'all' "
        f"AND Site_ID IS NULL AND Practitioner_ID IS NULL",
        tids,
    )
    result = {}
    for r in cur.fetchall():
        result.setdefault(r[1], {})[r[0]] = {
            'value':    float(r[2]) if r[2] is not None else None,
            'variance': float(r[3]) if r[3] is not None else None,
        }
    return result


def _fetch_metric_meta(cur):
    """Returns {metric_key: {range_type}} for all active metrics."""
    cur.execute("SELECT Metric_Key, Range_Type FROM Config.Metric_Definitions WHERE Is_Active = 1")
    return {r[0]: {'range_type': r[1] or 'above'} for r in cur.fetchall()}


def _wrap(key, value, targets, tids, fmt, metric_meta=None):
    """Returns {value, target, vs_target_pct, performance_class}.

    vs_target_pct > 0 always means beating target (sign accounts for range_type).
    performance_class: strong-green | weak-green | weak-red | strong-red | None.
    Variance is the average of per-tenant variance values from Input.Targets.
    """
    fval    = float(value) if value is not None else None
    tid_set = set(tids)
    meta    = (metric_meta or {}).get(key, {})
    range_t = meta.get('range_type', 'above')

    target_rows = {tid: v for tid, v in targets.get(key, {}).items() if tid in tid_set}
    target     = None
    vs_pct     = None
    perf_class = None

    if target_rows and fval is not None:
        tenant_values    = [v['value']    for v in target_rows.values() if v.get('value')    is not None]
        tenant_variances = [v['variance'] for v in target_rows.values() if v.get('variance') is not None]

        if not tenant_values:
            return {'value': fval, 'target': None, 'vs_target_pct': None, 'performance_class': None}

        combined = sum(tenant_values) if fmt in ('currency', 'count') else sum(tenant_values) / len(tenant_values)
        target   = round(combined, 4)
        variance = sum(tenant_variances) / len(tenant_variances) if tenant_variances else None

        if combined != 0:
            raw_pct = (fval - combined) / abs(combined) * 100   # positive = above target

            if range_t == 'within':
                dev_pct = abs(raw_pct)
                if variance is not None:
                    vs_pct = round(variance - dev_pct, 1)        # positive = inside band
                    if dev_pct <= variance / 2:
                        perf_class = 'strong-green'
                    elif dev_pct <= variance:
                        perf_class = 'weak-green'
                    elif dev_pct <= variance * 2:
                        perf_class = 'weak-red'
                    else:
                        perf_class = 'strong-red'
            else:
                signed = raw_pct if range_t == 'above' else -raw_pct
                vs_pct = round(signed, 1)
                if variance is not None:
                    if signed >= variance:
                        perf_class = 'strong-green'
                    elif signed >= 0:
                        perf_class = 'weak-green'
                    elif signed >= -variance:
                        perf_class = 'weak-red'
                    else:
                        perf_class = 'strong-red'
                else:
                    perf_class = 'strong-green' if signed >= 0 else 'strong-red'

    return {'value': fval, 'target': target, 'vs_target_pct': vs_pct, 'performance_class': perf_class}

# ── KPI functions (one per section) ──────────────────────────────────────────

def _kpis_revenue(cur, tids, period, site_id, pract_id, targets, metric_meta=None):
    # Revenue totals and patient count from Daily aggregate
    p1 = []
    tid_w  = _tid_in(tids, p1, alias='d')
    date_w = _pw('d.fk_Date', period, p1)
    site_w = _agg_sw(site_id, tids, p1)
    prac_w = _prw(pract_id, tids, p1, alias='d')
    cur.execute(f"""
        SELECT SUM(d.NHS_Revenue + d.Private_Revenue),
               SUM(d.NHS_Revenue),
               SUM(d.Private_Revenue),
               COUNT(DISTINCT d.fk_Patient)
        FROM Gold.Aggregate_Site_Patient_Practitioner_Daily d
        WHERE {tid_w} {date_w} {site_w} {prac_w}
    """, p1)
    row   = cur.fetchone()
    total = float(row[0]) if row[0] else 0.0
    nhs   = float(row[1]) if row[1] else 0.0
    priv  = float(row[2]) if row[2] else 0.0
    pts   = int(row[3])   if row[3] else 0
    rpp   = round(total / pts, 2) if pts else None

    # Worked hours deduplicated at practitioner-day level (Worked_Hours repeats per patient row)
    p2 = []
    tid_w2  = _tid_in(tids, p2, alias='d2')
    date_w2 = _pw('d2.fk_Date', period, p2)
    site_w2 = _agg_sw(site_id, tids, p2, alias='d2')
    prac_w2 = _prw(pract_id, tids, p2, alias='d2')
    cur.execute(f"""
        SELECT SUM(mx) FROM (
            SELECT MAX(d2.Worked_Hours) AS mx
            FROM Gold.Aggregate_Site_Patient_Practitioner_Daily d2
            WHERE {tid_w2} {date_w2} {site_w2} {prac_w2}
            GROUP BY d2.fk_Practitioner, d2.fk_Date, d2.fk_Site, d2.Tenant_ID
        ) sub
    """, p2)
    wh_row = cur.fetchone()
    worked = float(wh_row[0]) if wh_row and wh_row[0] else None
    rph    = round(total / worked, 2) if worked else None

    # Deposit ratio: % of open treatment plan items that have an invoice raised
    p3 = []
    tid_w3  = _tid_in(tids, p3, alias='tpi')
    date_w3 = _pw('tpi.fk_Date_Created', period, p3)
    prac_w3 = _prw(pract_id, tids, p3, alias='tpi')
    cur.execute(f"""
        SELECT
            SUM(CASE WHEN tpi.Completed=0 AND tpi.Invoice_ID IS NOT NULL THEN 1 ELSE 0 END)
                * 100.0 / NULLIF(SUM(CASE WHEN tpi.Completed=0 THEN 1 ELSE 0 END), 0)
        FROM Gold.Fact_Treatment_Plan_Items tpi
        WHERE {tid_w3} {date_w3} {prac_w3}
    """, p3)
    dep_row       = cur.fetchone()
    deposit_ratio = round(float(dep_row[0]), 1) if dep_row and dep_row[0] else None

    return {
        'total_revenue':       _wrap('total_revenue',       total,         targets, tids, 'currency', metric_meta),
        'nhs_revenue':         _wrap('nhs_revenue',         nhs,           targets, tids, 'currency', metric_meta),
        'private_revenue':     _wrap('private_revenue',     priv,          targets, tids, 'currency', metric_meta),
        'revenue_per_patient': _wrap('revenue_per_patient', rpp,           targets, tids, 'currency', metric_meta),
        'revenue_per_hour':    _wrap('revenue_per_hour',    rph,           targets, tids, 'currency', metric_meta),
        'deposit_ratio':       _wrap('deposit_ratio',       deposit_ratio, targets, tids, 'percent',  metric_meta),
    }


def _kpis_patients(cur, tids, period, site_id, pract_id, targets, metric_meta=None):
    # New patients: period + site + practitioner sensitive
    p1 = []
    tid_w  = _tid_in(tids, p1, alias='d')
    date_w = _pw('d.fk_Date', period, p1)
    site_w = _agg_sw(site_id, tids, p1)
    prac_w = _prw(pract_id, tids, p1, alias='d')
    cur.execute(f"""
        SELECT COUNT(DISTINCT d.fk_Patient)
        FROM Gold.Aggregate_Site_Patient_Practitioner_Daily d
        WHERE {tid_w} AND d.New_Patient = 1 {date_w} {site_w} {prac_w}
    """, p1)
    new_pts = int(cur.fetchone()[0] or 0)

    # Current-state patient metrics: active, retention, recall overdue (site filter only)
    p2 = []
    tid_w2  = _tid_in(tids, p2, alias='c')
    site_w2 = _agg_sw(site_id, tids, p2, alias='c')
    cur.execute(f"""
        SELECT SUM(CAST(c.Active_Patients   AS INT)),
               SUM(CAST(c.Retained_Patients AS INT)),
               COUNT(*),
               SUM(CASE WHEN c.Recall_Due=1 THEN 1 ELSE 0 END),
               SUM(CASE WHEN c.Recall_Due=1 AND c.Recall_Sent=0 THEN 1 ELSE 0 END)
        FROM Gold.Aggregate_Site_Patient_Current c
        WHERE {tid_w2} {site_w2}
    """, p2)
    row2      = cur.fetchone()
    active    = int(row2[0]) if row2[0] else 0
    retained  = int(row2[1]) if row2[1] else 0
    total_pts = int(row2[2]) if row2[2] else 0
    due_cnt   = int(row2[3]) if row2[3] else 0
    overdue_not_sent = int(row2[4]) if row2[4] else 0
    retention     = round(retained / total_pts * 100, 1) if total_pts else None
    overdue_ns_pct = round(overdue_not_sent / due_cnt * 100, 1) if due_cnt else None

    # Recall effectiveness from Fact_Recalls (not overdue / total)
    p3 = []
    tid_w3  = _tid_in(tids, p3, alias='r')
    date_w3 = _pw('r.fk_Date_Due', period, p3)
    cur.execute(f"""
        SELECT COUNT(*),
               SUM(CASE WHEN r.Days_Overdue > 0 THEN 1 ELSE 0 END)
        FROM Gold.Fact_Recalls r
        WHERE {tid_w3} {date_w3}
    """, p3)
    row3      = cur.fetchone()
    total_r   = int(row3[0]) if row3[0] else 0
    overdue_r = int(row3[1]) if row3[1] else 0
    recall_eff = round((total_r - overdue_r) / total_r * 100, 1) if total_r else None

    return {
        'new_patients':             _wrap('new_patients',             new_pts,        targets, tids, 'count',   metric_meta),
        'active_patients':          _wrap('active_patients',          active,         targets, tids, 'count',   metric_meta),
        'recall_compliance':        _wrap('recall_compliance',        recall_eff,     targets, tids, 'percent', metric_meta),
        'patient_retention':        _wrap('patient_retention',        retention,      targets, tids, 'percent', metric_meta),
        'recalls_overdue_not_sent': _wrap('recalls_overdue_not_sent', overdue_ns_pct, targets, tids, 'percent', metric_meta),
    }


def _kpis_treatment(cur, tids, period, site_id, pract_id, targets, metric_meta=None):
    # Acceptance rate and open courses from Fact_Treatment_Plan_Items
    p1 = []
    tid_w  = _tid_in(tids, p1, alias='tpi')
    date_w = _pw('tpi.fk_Date_Created', period, p1)
    prac_w = _prw(pract_id, tids, p1, alias='tpi')
    cur.execute(f"""
        SELECT
            COUNT(DISTINCT CASE WHEN tpi.Completed=0 AND tpi.Charged=0
                                THEN tpi.Treatment_Plan_ID END),
            SUM(CAST(tpi.Completed AS INT)) * 100.0 / NULLIF(COUNT(*), 0)
        FROM Gold.Fact_Treatment_Plan_Items tpi
        WHERE {tid_w} {date_w} {prac_w}
    """, p1)
    row  = cur.fetchone()
    open_courses    = int(row[0])             if row[0] is not None else 0
    acceptance_rate = round(float(row[1]), 1) if row[1] else None

    # Open courses without a future appointment (LEFT JOIN pattern, Fabric-safe)
    p2 = []
    tid_w2  = _tid_in(tids, p2, alias='tpi')
    prac_w2 = _prw(pract_id, tids, p2, alias='tpi')
    cur.execute(f"""
        SELECT COUNT(DISTINCT tpi.Treatment_Plan_ID)
        FROM Gold.Fact_Treatment_Plan_Items tpi
        LEFT JOIN Gold.Fact_Treatment_Appointments ta
            ON  ta.Treatment_Plan_ID = tpi.Treatment_Plan_ID
            AND ta.Tenant_ID         = tpi.Tenant_ID
            AND ta.fk_Date_Appointment >= Gold.fn_Get_Date_Key(CAST(GETDATE() AS DATE))
        WHERE tpi.Completed = 0
            AND {tid_w2} {prac_w2}
            AND ta.pk_Treatment_Appointment IS NULL
    """, p2)
    oc_no_appt = int(cur.fetchone()[0] or 0)

    # Exam ratio from Daily aggregate
    p3 = []
    tid_w3  = _tid_in(tids, p3, alias='d')
    date_w3 = _pw('d.fk_Date', period, p3)
    site_w3 = _agg_sw(site_id, tids, p3)
    prac_w3 = _prw(pract_id, tids, p3, alias='d')
    cur.execute(f"""
        SELECT SUM(d.Exam_Count) * 100.0 / NULLIF(SUM(d.Appointments), 0)
        FROM Gold.Aggregate_Site_Patient_Practitioner_Daily d
        WHERE {tid_w3} {date_w3} {site_w3} {prac_w3}
    """, p3)
    er_row     = cur.fetchone()
    exam_ratio = round(float(er_row[0]), 1) if er_row and er_row[0] else None

    return {
        'acceptance_rate':           _wrap('acceptance_rate',           acceptance_rate, targets, tids, 'percent', metric_meta),
        'open_courses':              _wrap('open_courses',              open_courses,    targets, tids, 'count',   metric_meta),
        'open_courses_without_appt': _wrap('open_courses_without_appt', oc_no_appt,     targets, tids, 'count',   metric_meta),
        'exam_ratio':                _wrap('exam_ratio',                exam_ratio,      targets, tids, 'percent', metric_meta),
    }


def _kpis_scheduling(cur, tids, period, site_id, pract_id, targets, metric_meta=None):
    # Appointment-level metrics from Daily aggregate
    p1 = []
    tid_w  = _tid_in(tids, p1, alias='d')
    date_w = _pw('d.fk_Date', period, p1)
    site_w = _agg_sw(site_id, tids, p1)
    prac_w = _prw(pract_id, tids, p1, alias='d')
    cur.execute(f"""
        SELECT SUM(d.Appointment_Hours),
               SUM(d.DNA_Appointments),
               SUM(d.Appointments),
               SUM(d.BBYL_Appointments)
        FROM Gold.Aggregate_Site_Patient_Practitioner_Daily d
        WHERE {tid_w} {date_w} {site_w} {prac_w}
    """, p1)
    row        = cur.fetchone()
    apt_hrs    = float(row[0]) if row[0] else 0.0
    dna_apts   = int(row[1])   if row[1] else 0
    total_apts = int(row[2])   if row[2] else 0
    bbyl_apts  = int(row[3])   if row[3] else 0
    dna_rate   = round(dna_apts  / total_apts * 100, 1) if total_apts else None
    bbyl_pct   = round(bbyl_apts / total_apts * 100, 1) if total_apts else None

    # Worked hours deduplicated at practitioner-day level
    p2 = []
    tid_w2  = _tid_in(tids, p2, alias='d2')
    date_w2 = _pw('d2.fk_Date', period, p2)
    site_w2 = _agg_sw(site_id, tids, p2, alias='d2')
    prac_w2 = _prw(pract_id, tids, p2, alias='d2')
    cur.execute(f"""
        SELECT SUM(mx) FROM (
            SELECT MAX(d2.Worked_Hours) AS mx
            FROM Gold.Aggregate_Site_Patient_Practitioner_Daily d2
            WHERE {tid_w2} {date_w2} {site_w2} {prac_w2}
            GROUP BY d2.fk_Practitioner, d2.fk_Date, d2.fk_Site, d2.Tenant_ID
        ) sub
    """, p2)
    wh_row     = cur.fetchone()
    worked     = float(wh_row[0]) if wh_row and wh_row[0] else None
    chair_util = round(apt_hrs / worked * 100, 1) if worked else None

    # Next free diary slots from Practitioner_Current (site filter only, no period)
    p3 = []
    tid_w3  = _tid_in(tids, p3, alias='c')
    site_w3 = _agg_sw(site_id, tids, p3, alias='c')
    cur.execute(f"""
        SELECT MIN(c.Days_Until_Next_30_Mins), MIN(c.Days_Until_Next_1_Hour_Free)
        FROM Gold.Aggregate_Site_Practitioner_Current c
        WHERE {tid_w3} {site_w3}
    """, p3)
    sl_row = cur.fetchone()
    days30 = int(sl_row[0]) if sl_row and sl_row[0] is not None else None
    days60 = int(sl_row[1]) if sl_row and sl_row[1] is not None else None

    return {
        'chair_utilisation':     _wrap('chair_utilisation',     chair_util, targets, tids, 'percent', metric_meta),
        'dna_rate':              _wrap('dna_rate',              dna_rate,   targets, tids, 'percent', metric_meta),
        'days_until_30min_free': _wrap('days_until_30min_free', days30,     targets, tids, 'count',   metric_meta),
        'days_until_1hr_free':   _wrap('days_until_1hr_free',   days60,     targets, tids, 'count',   metric_meta),
        'book_before_you_leave': _wrap('book_before_you_leave', bbyl_pct,   targets, tids, 'percent', metric_meta),
    }


def _kpis_nhs(cur, tids, period, site_id, pract_id, targets, metric_meta=None):
    return {}

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
        conn            = _fabric_conn()
        conn.autocommit = True   # Fabric Warehouse requires autocommit for DML
        cur             = conn.cursor()
        _, client_id, tids, _ = _get_user_info(cur, upn)
        if client_id is None:
            conn.close()
            return jsonify({'error': 'Forbidden'}), 403

        rows         = request.get_json(force=True) or []
        allowed_tids = set(tids)

        for row in rows:
            tid      = int(row['tenant_id'])
            metric   = str(row['metric'])
            value    = row.get('value')
            variance = row.get('variance')
            if tid not in allowed_tids:
                continue
            cur.execute(
                "DELETE FROM Input.Targets "
                "WHERE Tenant_ID = ? AND Metric = ? "
                "AND Period_Type = 'all_time' AND Period_Value = 'all' "
                "AND Site_ID IS NULL AND Practitioner_ID IS NULL",
                [tid, metric],
            )
            if value is not None:
                cur.execute(
                    "INSERT INTO Input.Targets "
                    "(Tenant_ID, Site_ID, Practitioner_ID, Metric, Period_Type, Period_Value, "
                    " Target_Value, Variance, DW_Created_At, DW_Updated_At) "
                    "VALUES (?, NULL, NULL, ?, 'all_time', 'all', ?, ?, GETUTCDATE(), GETUTCDATE())",
                    [tid, metric, float(value),
                     float(variance) if variance is not None else None],
                )

        conn.close()
        return jsonify({'ok': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500



if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 5000)), debug=True)
