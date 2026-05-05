from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
import msal
import requests
import pyodbc
import os
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__, static_folder='.')
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
    'patients':   os.environ.get('REPORT_ID_PATIENT',   ''),
    'treatment':  os.environ.get('REPORT_ID_TREATMENT', ''),
    'scheduling': os.environ.get('REPORT_ID_SCHEDULE',  ''),
    'nhs':        os.environ.get('REPORT_ID_NHS',       ''),
}


def _pbi_token():
    """Acquire a service-principal access token for the Power BI REST API."""
    result = msal.ConfidentialClientApplication(
        CLIENT_ID,
        authority=PBI_AUTHORITY,
        client_credential=CLIENT_SECRET,
    ).acquire_token_for_client(scopes=PBI_SCOPE)
    if 'access_token' not in result:
        raise RuntimeError(result.get('error_description', 'MSAL token acquisition failed'))
    return result['access_token']


def _pbi_delegated_token():
    """Acquire a delegated token via ROPC — required for executeQueries (Delegated-only API)."""
    result = msal.ConfidentialClientApplication(
        CLIENT_ID,
        authority=PBI_AUTHORITY,
        client_credential=CLIENT_SECRET,
    ).acquire_token_by_username_password(
        username=USERNAME,
        password=PASSWORD,
        scopes=PBI_SCOPE,
    )
    if 'access_token' not in result:
        raise RuntimeError(result.get('error_description', 'MSAL delegated token acquisition failed'))
    return result['access_token']



def _fabric_conn():
    """Open a pyodbc connection to Fabric Warehouse using AAD password auth."""
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


@app.route('/')
def index():
    return send_from_directory('.', 'index.html')


@app.route('/api/embed-token')
def embed_token():
    """
    Returns an embed token, embed URL, and report ID for a named report.
    Query param: ?report=revenue  (defaults to 'revenue')
    """
    report_name = request.args.get('report', 'revenue')
    report_id   = REPORTS.get(report_name)

    if not report_id:
        return jsonify({'error': f"Report '{report_name}' not configured"}), 404

    try:
        token   = _pbi_token()
        headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

        # Fetch report metadata (gives us the embedUrl)
        r = requests.get(
            f'{PBI_BASE}/groups/{WORKSPACE_ID}/reports/{report_id}',
            headers=headers, timeout=10,
        )
        r.raise_for_status()
        report_meta = r.json()
        embed_url   = report_meta['embedUrl']
        dataset_id  = report_meta['datasetId']

        # Fabric-backed datasets require effectiveIdentity (used for RLS later)
        r2 = requests.post(
            f'{PBI_BASE}/groups/{WORKSPACE_ID}/reports/{report_id}/GenerateToken',
            headers=headers,
            json={
                'accessLevel': 'View',
                'identities': [{
                    'username': USERNAME,
                    'roles':    REPORT_ROLES,
                    'datasets': [dataset_id],
                }],
            },
            timeout=10,
        )
        r2.raise_for_status()

        return jsonify({
            'token':    r2.json()['token'],
            'embedUrl': embed_url,
            'reportId': report_id,
        })

    except requests.HTTPError as e:
        return jsonify({'error': str(e), 'detail': e.response.text}), 502
    except Exception as e:
        return jsonify({'error': str(e)}), 500


def _dax_query(dax):
    """Run a DAX query against the semantic model and return rows as a list of dicts."""
    token   = _pbi_delegated_token()
    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
    r = requests.post(
        f'{PBI_BASE}/groups/{WORKSPACE_ID}/datasets/{DATASET_ID}/executeQueries',
        headers=headers,
        json={
            'queries':            [{'query': dax}],
            'serializerSettings': {'includeNulls': True},
        },
        timeout=15,
    )
    r.raise_for_status()
    rows = r.json()['results'][0]['tables'][0].get('rows', [])
    # Strip table-prefix from column names ("List Practice Sites[Site Name]" → "Site Name")
    return [{k.split('[')[-1].rstrip(']'): v for k, v in row.items()} for row in rows]


@app.route('/api/filters')
def filters():
    """Returns active sites and practitioners for the logged-in user's tenant."""
    active_only = request.args.get('active_only', '1') == '1'
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        tid  = _get_tenant_id(cur)

        cur.execute(
            "SELECT Site_ID, Site_Name "
            "FROM   Gold.Dim_Practice_Sites "
            "WHERE  Tenant_ID = ? AND Site_Active = 1 "
            "ORDER BY Site_Name",
            tid,
        )
        sites = [{'id': str(r[0]), 'name': r[1]} for r in cur.fetchall()]

        active_w = "AND Active = 1" if active_only else ""
        cur.execute(
            f"SELECT Practitioner_ID, Full_Name "
            f"FROM   Gold.Dim_Practitioners "
            f"WHERE  Tenant_ID = ? {active_w} "
            f"ORDER BY Full_Name",
            tid,
        )
        practitioners = [{'id': str(r[0]), 'name': r[1]} for r in cur.fetchall()]

        conn.close()
        return jsonify({'sites': sites, 'practitioners': practitioners})

    except Exception as e:
        return jsonify({'sites': [], 'practitioners': [], '_error': str(e)})


# ── KPI helpers ───────────────────────────────────────────────────────────────

def _get_tenant_id(cur):
    """Return Tenant_ID for the master account. Temporary until per-user auth is added."""
    cur.execute(
        "SELECT Tenant_ID FROM Security.Application_Users WHERE User_UPN = ?",
        USERNAME,
    )
    row = cur.fetchone()
    return row[0] if row else 1


def _pw(date_col, period, params):
    """Append a period WHERE fragment (current year). Mutates params."""
    if period and period != 'all':
        params.append(period)
        return (f"AND {date_col} IN "
                f"(SELECT fk_Date FROM Gold.Dim_Date_Grouping WHERE Date_Grouping = ?)")
    return ""


def _pyw(date_col, period, params):
    """Append a period WHERE fragment (prior year). Mutates params."""
    if period and period != 'all':
        params.append(period)
        return (f"AND {date_col} IN "
                f"(SELECT fk_Date_Previous_Year FROM Gold.Dim_Date_Grouping WHERE Date_Grouping = ?)")
    return ""


def _sw(site_id, tid, params, alias='fi'):
    """Append a site WHERE fragment. Mutates params."""
    if site_id and site_id != 'all':
        params.extend([str(site_id), tid])
        return (f"AND {alias}.fk_Practice_Site IN "
                f"(SELECT pk_Practice_Site FROM Gold.Dim_Practice_Sites "
                f"WHERE Site_ID = ? AND Tenant_ID = ?)")
    return ""


def _prw(pract_id, tid, params, alias='fi'):
    """Append a practitioner WHERE fragment. Mutates params."""
    if pract_id and pract_id != 'all':
        params.extend([str(pract_id), tid])
        return (f"AND {alias}.fk_Practitioner IN "
                f"(SELECT pk_Practitioner FROM Gold.Dim_Practitioners "
                f"WHERE CAST(Practitioner_ID AS VARCHAR) = ? AND Tenant_ID = ?)")
    return ""


def _pct_delta(cur_val, py_val):
    if cur_val is None or py_val is None or py_val == 0:
        return None
    return round((float(cur_val) - float(py_val)) / abs(float(py_val)) * 100, 1)


def _kpi(value, delta_pct=None):
    return {'value': float(value) if value is not None else None, 'delta_pct': delta_pct}


def _invoice_agg(cur, tid, period, site_id, pract_id, prior=False):
    """Run Invoice_Items aggregation for current or prior year."""
    params = [tid]
    date_w = _pyw('fi.fk_Date_Invoice', period, params) if prior \
             else _pw('fi.fk_Date_Invoice', period, params)
    site_w = _sw(site_id, tid, params)
    prac_w = _prw(pract_id, tid, params)
    cur.execute(f"""
        SELECT SUM(fi.Invoice_Amount),
               SUM(fi.Invoice_NHS_Amount),
               SUM(fi.Invoice_Amount - fi.Invoice_NHS_Amount),
               SUM(fi.Invoice_Amount_Outstanding),
               COUNT(DISTINCT fi.fk_Patient)
        FROM   Gold.Fact_Invoice_Items fi
        WHERE  fi.Tenant_ID = ? {date_w} {site_w} {prac_w}
    """, params)
    return cur.fetchone()


def _kpis_revenue(cur, tid, period, site_id, pract_id):
    c = _invoice_agg(cur, tid, period, site_id, pract_id)
    p = _invoice_agg(cur, tid, period, site_id, pract_id, prior=True)
    total = float(c[0]) if c[0] else 0
    pts   = int(c[4])   if c[4] else 0
    py_pts = int(p[4])  if p[4] else 0
    rpp    = round(total / pts, 2) if pts else None
    py_rpp = round(float(p[0]) / py_pts, 2) if (p[0] and py_pts) else None
    return {
        'total_revenue':       _kpi(total,        _pct_delta(c[0], p[0])),
        'nhs_revenue':         _kpi(c[1],         _pct_delta(c[1], p[1])),
        'private_revenue':     _kpi(c[2],         _pct_delta(c[2], p[2])),
        'revenue_per_patient': _kpi(rpp,          _pct_delta(rpp,  py_rpp)),
    }


def _kpis_cashflow(cur, tid, period, site_id, pract_id):
    c = _invoice_agg(cur, tid, period, site_id, pract_id)
    p = _invoice_agg(cur, tid, period, site_id, pract_id, prior=True)
    inv  = float(c[0]) if c[0] else 0
    out  = float(c[3]) if c[3] else 0
    coll = inv - out
    py_inv  = float(p[0]) if p[0] else 0
    py_out  = float(p[3]) if p[3] else 0
    py_coll = py_inv - py_out
    rate    = round(coll / inv * 100, 1) if inv else None
    py_rate = round(py_coll / py_inv * 100, 1) if py_inv else None
    return {
        'total_invoiced':  _kpi(inv,  _pct_delta(inv,  py_inv)),
        'total_collected': _kpi(coll, _pct_delta(coll, py_coll)),
        'outstanding':     _kpi(out,  _pct_delta(out,  py_out)),
        'collection_rate': _kpi(rate, _pct_delta(rate, py_rate)),
    }


def _kpis_patients(cur, tid, period, site_id, pract_id):
    # Active patients — point-in-time, no date filter
    cur.execute(
        "SELECT COUNT(*) FROM Gold.Dim_Patients "
        "WHERE Tenant_ID = ? AND Active = 1 AND pk_Patient > 0",
        tid,
    )
    active = int(cur.fetchone()[0])

    # New patients in period — filter by Patient_Created_Date via date key
    params = [tid]
    date_w = _pw('Gold.fn_Get_Date_Key(CAST(dp.Patient_Created_Date AS DATE))',
                 period, params)
    cur.execute(f"""
        SELECT COUNT(*)
        FROM   Gold.Dim_Patients dp
        WHERE  dp.Tenant_ID = ? {date_w} AND dp.pk_Patient > 0
    """, params)
    new_pts = int(cur.fetchone()[0])

    # Recalls in period
    params_r = [tid]
    date_r = _pw('r.fk_Date_Due', period, params_r)
    cur.execute(f"""
        SELECT COUNT(*),
               SUM(CASE WHEN r.Days_Overdue > 0 THEN 1 ELSE 0 END)
        FROM   Gold.Fact_Recalls r
        WHERE  r.Tenant_ID = ? {date_r}
    """, params_r)
    row = cur.fetchone()
    total_r   = int(row[0]) if row[0] else 0
    overdue_r = int(row[1]) if row[1] else 0
    compliance = round((total_r - overdue_r) / total_r * 100, 1) if total_r else None

    return {
        'active_patients':   _kpi(active),
        'new_patients':      _kpi(new_pts),
        'recall_compliance': _kpi(compliance),
        'overdue_recalls':   _kpi(overdue_r),
    }


def _kpis_treatment(cur, tid, period, site_id, pract_id):
    params = [tid]
    date_w = _pw('tpi.fk_Date_Created', period, params)
    prac_w = _prw(pract_id, tid, params, alias='tpi')
    cur.execute(f"""
        SELECT COUNT(DISTINCT tpi.Treatment_Plan_ID),
               SUM(CASE WHEN tpi.Completed = 1 THEN 1 ELSE 0 END),
               COUNT(*),
               AVG(CASE WHEN tpi.Completed = 1 THEN tpi.Price END),
               SUM(CASE WHEN tpi.Completed = 0 AND tpi.Charged = 0
                        THEN tpi.Price ELSE 0 END)
        FROM   Gold.Fact_Treatment_Plan_Items tpi
        WHERE  tpi.Tenant_ID = ? {date_w} {prac_w}
    """, params)
    row   = cur.fetchone()
    plans = int(row[0]) if row[0] else 0
    comp  = int(row[1]) if row[1] else 0
    total = int(row[2]) if row[2] else 0
    rate  = round(comp / total * 100, 1) if total else None
    return {
        'plans_presented':    _kpi(plans),
        'acceptance_rate':    _kpi(rate),
        'avg_accepted_value': _kpi(row[3]),
        'declined_value':     _kpi(row[4] if row[4] else 0),
    }


def _kpis_nhs(cur, tid, period, site_id, pract_id):
    params = [tid]
    date_w = _pw('fc.fk_Date_Start', period, params)
    cur.execute(f"""
        SELECT SUM(fc.UDA_Delivered),
               SUM(fc.UDA_Target),
               SUM(fc.Contract_Value)
        FROM   Gold.Fact_Contracts fc
        WHERE  fc.Tenant_ID = ? {date_w}
    """, params)
    row       = cur.fetchone()
    delivered = float(row[0]) if row[0] else 0
    target    = float(row[1]) if row[1] else 0
    value     = float(row[2]) if row[2] else 0
    achievement = round(delivered / target * 100, 1) if target else None
    vpu         = round(value / delivered, 2)         if delivered else None
    return {
        'uda_delivered':   _kpi(delivered),
        'uda_target':      _kpi(target),
        'uda_achievement': _kpi(achievement),
        'value_per_uda':   _kpi(vpu),
    }


def _kpis_scheduling(cur, tid, period, site_id, pract_id):
    params = [tid]
    date_w = _pw('apt.fk_Date_Start', period, params)
    site_w = _sw(site_id, tid, params, alias='apt')
    prac_w = _prw(pract_id, tid, params, alias='apt')
    cur.execute(f"""
        SELECT COUNT(*),
               SUM(CASE WHEN apt.Is_DNA       = 1 THEN 1 ELSE 0 END),
               SUM(CASE WHEN apt.Is_Cancelled = 1 THEN 1 ELSE 0 END)
        FROM   Gold.Fact_Appointments apt
        WHERE  apt.Tenant_ID = ? {date_w} {site_w} {prac_w}
    """, params)
    row   = cur.fetchone()
    total = int(row[0]) if row[0] else 0
    dna   = int(row[1]) if row[1] else 0
    canc  = int(row[2]) if row[2] else 0
    return {
        'total_appointments': _kpi(total),
        'dna_rate':           _kpi(round(dna  / total * 100, 1) if total else None),
        'cancellations':      _kpi(canc),
    }


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route('/api/me')
def me():
    """Returns display name, tenant, and practice name for the current master account.
    Temporary — will use the logged-in user's UPN once MSAL.js auth is added."""
    try:
        conn = _fabric_conn()
        cur  = conn.cursor()
        cur.execute(
            "SELECT Display_Name, Tenant_ID "
            "FROM   Security.Application_Users "
            "WHERE  User_UPN = ?",
            USERNAME,
        )
        row = cur.fetchone()
        if not row:
            conn.close()
            return jsonify({'display_name': USERNAME, 'tenant_id': 1, 'practice_name': None})
        tid = row[1]
        cur.execute(
            "SELECT TOP 1 Practice_Name "
            "FROM   Gold.Dim_Practice_Sites "
            "WHERE  Tenant_ID = ?",
            tid,
        )
        prow = cur.fetchone()
        conn.close()
        return jsonify({
            'display_name':  row[0] or USERNAME,
            'tenant_id':     tid,
            'practice_name': prow[0] if prow else None,
        })
    except Exception as e:
        return jsonify({'display_name': USERNAME, 'tenant_id': 1, 'practice_name': None, '_error': str(e)})


@app.route('/api/kpis')
def kpis():
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
        tid  = _get_tenant_id(cur)
        result = fn(cur, tid, period, site_id, pract_id)
        conn.close()
        return jsonify(result)
    except Exception as e:
        return jsonify({'_error': str(e)}), 500


if __name__ == '__main__':
    app.run(debug=True, port=5000)
