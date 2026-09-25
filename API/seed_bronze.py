"""Seed a synthetic demo practice straight into Bronze.

    python API/seed_bronze.py --tenant 11                 # anchored to today
    python API/seed_bronze.py --tenant 11 --as-of 2026-09-25
    python API/seed_bronze.py --tenant 11 --dry-run       # generate and map, write nothing

WHY BRONZE AND NOT STAGE. Ingest_Dentally writes the lakehouse stage tables with
mode("overwrite") -- the WHOLE table, not a tenant slice -- so anything seeded into stage_* is
erased the next time the real practice is ingested. Bronze is the opposite: its load procedures
only insert-if-absent and update-if-changed FROM Stage, and have no delete step at all, so rows
for a tenant that appears nowhere in Stage are simply never touched. The demo practice therefore
sits in Bronze permanently and inertly, and Silver and Gold treat it as one more tenant with no
changes anywhere.

WHY IT CANNOT CONTAMINATE THE REAL PRACTICE. Two gates, both structural rather than rules
somebody has to remember:
  * the ingest loops Key Vault tokens (`for tid, cfg in TOKENS.items()`), not Audit.Tenants, and
    the demo tenant has no Dentally token -- so it is never pulled, and cannot be
  * billing builds from Security.Application_Users, and generated Dentally users never land
    there -- so the demo practice cannot appear on an invoice or in affiliate commission
The ingest's incremental watermark is also per-tenant (`bronze_watermark(tenant_id, ...)`), so
generated rows cannot drag the real practice's cutoff forward and make it skip real records.

DELETE-THEN-INSERT, NOT MERGE. The practice is fictional and wholly derived, so there is nothing
an incremental load would protect. A full replace also makes the weekly rebuild idempotent: some
generated identities are date-derived (`_u5("diary", tid, pid, str(cur))`), so a merge would
accumulate orphaned diary rows every week and chair utilisation would drift upward for ever.

The as-of date is what keeps it current: generate_data builds six years back and ~14 months
forward from it, so re-running with today's date moves the whole practice rather than ageing it.
"""
import argparse, json, os, struct, subprocess, sys
from datetime import date, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

DEV_SERVER = ('emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem'
              '.datawarehouse.fabric.microsoft.com')

# stage/table key from the generator  ->  Bronze table
TABLE_MAP = [
    ('practice',                'Practice'),
    ('sites',                   'Sites'),
    ('users',                   'Users'),
    ('practitioners',           'Practitioners'),
    ('payment_plans',           'Payment_Plans'),
    ('treatments',              'Treatments'),
    ('treatment_categories',    'Treatment_Categories'),
    ('acquisition_sources',     'Acquisition_Sources'),
    ('cancellation_reasons',    'Cancellation_Reasons'),
    ('waiting_lists',           'Waiting_Lists'),
    ('sundries',                'Sundries'),
    ('contracts',               'Contracts'),
    ('fees',                    'Fees'),
    ('diary_breaks',            'Practitioner_Diary_Breaks'),
    ('rooms',                   'Rooms'),
    ('patients',                'Patients'),
    ('diary_entries',           'Practitioner_Diary'),
    ('appointments',            'Appointments'),
    ('invoices',                'Invoices'),
    ('invoice_items',           'Invoice_Items'),
    ('payments',                'Payments'),
    ('treatment_plans',         'Treatment_Plans'),
    ('treatment_plan_items',    'Treatment_Plan_Items'),
    ('recalls',                 'Recalls'),
    ('nhs_claims',              'NHS_Claims'),
    ('patient_stats',           'Patient_Stats'),
    ('payment_allocations',     'Payment_Allocations'),
    ('payment_explanations',    'Payment_Explanations'),
    ('treatment_appts',         'Treatment_Appointments'),
    ('patient_referrals',       'Patient_Referrals'),
]

# Where the API field does NOT follow the mechanical rule. Harvested from the Bronze load
# procedures, which are the authoritative stage->Bronze mapping, then hand-checked against
# INFORMATION_SCHEMA -- a regex over SQL produced a few plausible-looking false positives
# ('cast', 'coalesce'), and a wrong mapping here is a silently empty column in Gold.
#
# The naming is genuinely inconsistent between tables and that is the whole reason this map
# exists: Appointments keys on ID, Patients on Patient_ID, and Practice really does have a '#'
# in its opening-hours columns.
FIELD_OVERRIDES = {
    'Patients':      {'id': 'Patient_ID', 'preferred_phone_number': 'Preferred_Phone'},
    'Sites':         {'id': 'Site_ID'},
    'Payments':      {'id': 'Payment_ID'},
    'Fees':          {'id': 'Fee_ID'},
    'Practitioners': {'id': 'Practitioner_ID', 'site_id': 'Practitioner_Site_ID',
                      'gdc_number': 'Practitioner_GDC_Number',
                      'nhs_number': 'Practitioner_NHS_Number',
                      'default_contract_id': 'Practitioner_Default_Contract_ID',
                      'colour': 'Practitioner_Colour'},
    'Payment_Plans': {'id': 'Payment_Plan_ID', 'name': 'Payment_Plan_Name',
                      'created_at': 'Payment_Plan_Created_At',
                      'colour': 'Payment_Plan_Colour',
                      'patient_friendly_name': 'Payment_Plan_Patient_Friendly_Name',
                      'site_id': 'Payment_Plan_Site_ID'},
    'Practice':      {'id': 'Practice_ID', 'name': 'Practice_Name',
                      **{f'oh_{d}_{e}': f'Oh_{d.capitalize()}#{e}'
                         for d in ('mon', 'tues', 'wed', 'thur', 'fri', 'sat', 'sun')
                         for e in ('open', 'close')}},
    'Practitioner_Diary': {'date': 'Day'},
    # The Finance report groups on these, so an unmapped Class would leave every Xero line
    # unclassified and the Revenue vs Costs page empty.
    'Xero_Accounts': {'type': 'Account_Type', 'class': 'Account_Class'},
}

# Acronyms the warehouse always capitalises in full (dbo.CapitaliseSnakeCase keeps the same list).
ACRONYMS = {'id', 'nhs', 'uda', 'uoa', 'sms', 'dw'}


def to_column(field: str) -> str:
    """snake_case API field -> the warehouse's column spelling. use_sms -> Use_SMS."""
    return '_'.join(p.upper() if p.lower() in ACRONYMS else p.capitalize()
                    for p in field.split('_'))


def connect(server: str, database: str = 'WH_Dentally'):
    import pyodbc
    tok = subprocess.check_output(
        ['az', 'account', 'get-access-token', '--resource', 'https://database.windows.net',
         '--query', 'accessToken', '-o', 'tsv'], shell=True).decode().strip().encode('utf-16-le')
    ts = struct.pack(f'<I{len(tok)}s', len(tok), tok)
    cs = (f'Driver={{ODBC Driver 18 for SQL Server}};Server={server},1433;'
          f'Database={database};Encrypt=yes;TrustServerCertificate=no;')
    # autocommit: the deletes and inserts are independent per table and a partial run is
    # recoverable by re-running, whereas one open transaction over ~200k rows is not.
    return pyodbc.connect(cs, attrs_before={1256: ts}, autocommit=True)


def bronze_columns(cur, table):
    """Column names AND types. The normal path reaches Bronze via TRY_CAST from all-string stage
    tables, so the types only matter when writing direct -- which is what this does."""
    cur.execute("SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH "
                "FROM INFORMATION_SCHEMA.COLUMNS "
                "WHERE TABLE_SCHEMA='Bronze' AND TABLE_NAME=? ORDER BY ORDINAL_POSITION", table)
    rows = cur.fetchall()
    return [r[0] for r in rows], {r[0]: (r[1], r[2]) for r in rows}


NUMERIC = {'int', 'bigint', 'smallint', 'tinyint', 'decimal', 'numeric', 'float', 'real', 'money'}


def coerce(v, dtype, maxlen):
    """Bind-ready value for this column, or None.

    fast_executemany binds by declared type and will not quietly convert for you, so a string in
    a decimal column fails the whole batch with 'Invalid character value for cast specification'
    -- which names neither the column nor the row.
    """
    if v is None or v == '':
        return None
    if dtype in NUMERIC:
        try:
            f = float(v)
        except (TypeError, ValueError):
            return None
        return int(f) if dtype in ('int', 'bigint', 'smallint', 'tinyint') else f
    if dtype in ('date', 'datetime2', 'datetime', 'smalldatetime'):
        # A string will NOT bind to a datetime2 under fast_executemany -- it fails the whole
        # batch with 'Invalid character value for cast specification', naming neither column nor
        # row. Parse to a real date/datetime, and drop anything unparseable rather than poison
        # the batch: Bronze is a landing layer and the normal path TRY_CASTs these anyway.
        if isinstance(v, datetime):
            return v.date() if dtype == 'date' else v
        if isinstance(v, date):
            return v if dtype == 'date' else datetime(v.year, v.month, v.day)
        t = str(v).strip().replace('Z', '+00:00')
        for cut in (t, t[:19], t[:10]):
            try:
                d = datetime.fromisoformat(cut)
                return d.date() if dtype == 'date' else d.replace(tzinfo=None)
            except ValueError:
                continue
        return None
    if dtype == 'bit':
        if isinstance(v, bool):
            return 1 if v else 0
        return 1 if str(v).strip().lower() in ('true', '1', 'yes') else 0
    s = str(v)
    # Truncate rather than fail: Bronze is a landing layer and a demo practice is not worth a
    # failed batch over a long free-text field.
    return s[:maxlen] if maxlen and maxlen > 0 and len(s) > maxlen else s


def flatten(v):
    """Bronze is a raw landing layer of scalars; nested API structures land as JSON text."""
    if isinstance(v, (dict, list)):
        return json.dumps(v)
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    return v


def seed_table(cur, tenant_id, table, records, loaded_at, dry_run, report):
    cols, types = bronze_columns(cur, table)
    if not cols:
        report.append((table, 0, 0, 'NO SUCH BRONZE TABLE'))
        return
    colset = {c.lower(): c for c in cols}

    rows, mapped, unmapped = [], set(), set()
    for rec in records:
        row = {}
        for k, v in rec.items():
            ov = FIELD_OVERRIDES.get(table, {}).get(k.lower())
            c = ((colset.get(ov.lower()) if ov else None)
                 or colset.get(to_column(k).lower())
                 or colset.get(k.lower()))
            if c:
                row[c] = flatten(v)
                mapped.add(c)
            else:
                unmapped.add(k)
        if 'Tenant_ID' in colset.values():
            row['Tenant_ID'] = tenant_id
        for dwc in ('DW_Loaded_At', 'Load_Timestamp'):
            if dwc in cols:
                row[dwc] = loaded_at
        rows.append(row)

    # Every row must present the same column list for executemany.
    use = [c for c in cols if c in mapped or c in ('Tenant_ID', 'DW_Loaded_At', 'Load_Timestamp')]
    if not use:
        report.append((table, len(records), 0, 'NOTHING MAPPED'))
        return

    if not dry_run:
        cur.execute(f"DELETE FROM Bronze.[{table}] WHERE Tenant_ID = ?", tenant_id)
        if rows:
            # ==> MULTI-ROW VALUES, NOT executemany. <== Measured against this warehouse:
            # executemany with fast_executemany managed 3.5 rows/s -- 340k rows would take 27
            # HOURS -- because Fabric pays a round trip per row. One INSERT carrying many VALUES
            # tuples ran at 273 rows/s, 78x faster, which puts a full reseed at ~20 minutes.
            #
            # SQL Server caps a statement at 2100 parameters, so the rows per statement depend on
            # how wide the table is. Exceeding it fails the whole batch.
            collist = ','.join('[' + c + ']' for c in use)
            per = max(1, min(100, 2000 // max(1, len(use))))
            data = [[coerce(r.get(c), *types[c]) for c in use] for r in rows]
            one = '(' + ','.join('?' * len(use)) + ')'
            for i in range(0, len(data), per):
                chunk = data[i:i + per]
                sql = (f"INSERT INTO Bronze.[{table}] ({collist}) VALUES "
                       + ','.join([one] * len(chunk)))
                cur.execute(sql, [v for r in chunk for v in r])

    note = ''
    if unmapped:
        # Loud on purpose: a silently dropped field is a column of NULLs in Gold and a metric
        # that quietly reads zero, which is exactly the kind of wrong a demo must not be.
        note = 'UNMAPPED: ' + ', '.join(sorted(unmapped)[:6])
    report.append((table, len(records), len(use), note))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tenant', type=int, required=True)
    ap.add_argument('--as-of', default=None, help='YYYY-MM-DD; default today')
    ap.add_argument('--server', default=os.environ.get('FABRIC_SERVER', DEV_SERVER))
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    as_of = a.as_of or date.today().isoformat()
    # generate_data reads this at import, so it must be set first.
    os.environ['GENERATE_AS_OF'] = as_of

    from generate_data import generate_tenant
    from seed_tenants import SEED_TENANTS, generate_xero_finance

    if a.tenant not in SEED_TENANTS:
        sys.exit(f'No definition for tenant {a.tenant}. Known: {sorted(SEED_TENANTS)}')
    tdef = SEED_TENANTS[a.tenant]
    print(f"Tenant {a.tenant}: {tdef['practice']['name']}  "
          f"({tdef['n_patients']} patients, as-of {as_of})")

    data = generate_tenant(tdef)
    loaded_at = datetime.utcnow().replace(microsecond=0).isoformat()

    xa, xl, xo, xt = generate_xero_finance(tdef, data, loaded_at)
    # xo is a single org dict, not a list -- seed_onelake appends it where it extends the others.
    extra = [('Xero_Orgs', [xo] if isinstance(xo, dict) else (xo or [])),
             ('Xero_Accounts', xa), ('Xero_Lines', xl), ('Xero_Tracking', xt)]

    conn = connect(a.server)
    cur = conn.cursor()
    report = []
    try:
        for key, table in TABLE_MAP:
            recs = data.get(key) or []
            if key == 'practice' and isinstance(recs, dict):
                recs = [recs]
            seed_table(cur, a.tenant, table, recs, loaded_at, a.dry_run, report)
        for table, recs in extra:
            seed_table(cur, a.tenant, table, recs or [], loaded_at, a.dry_run, report)
    finally:
        conn.close()

    print(f"\n{'table':<28}{'records':>9}{'cols':>6}  note")
    total = 0
    for t, n, c, note in report:
        total += n
        print(f'{t:<28}{n:>9,}{c:>6}  {note}')
    print(f"{'TOTAL':<28}{total:>9,}")
    if a.dry_run:
        print('\nDRY RUN — nothing written.')


if __name__ == '__main__':
    main()
