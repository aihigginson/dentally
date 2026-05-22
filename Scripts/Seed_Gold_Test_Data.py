#!/usr/bin/env python3
"""
Seed_Gold_Test_Data.py
Populates 3 years of synthetic Gold-layer data for Tenant_ID=1.

Tables written:
  Gold.Dim_Tenants
  Gold.Dim_Practice_Sites
  Gold.Dim_Practitioners
  Gold.Dim_Patients
  Gold.Aggregate_Site_Patient_Practitioner_Daily
  Gold.Aggregate_Site_Patient_Current
  Gold.Aggregate_Site_Practitioner_Current
  Gold.Fact_Recalls
  Input.Targets

Usage:
  python Seed_Gold_Test_Data.py
  (reads FABRIC_SERVER, FABRIC_DB, PBI_USERNAME, PBI_PASSWORD from .env)
"""

import os, sys, random, math
from datetime import date, datetime, timedelta, time as dtime
from dotenv import load_dotenv

try:
    import pyodbc
except ImportError:
    sys.exit("pyodbc not installed. Run: pip install pyodbc")

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', 'Web', '.env'))

FABRIC_SERVER = os.environ['FABRIC_SERVER']
FABRIC_DB     = os.environ.get('FABRIC_DB', 'WH_Dentally')
USERNAME      = os.environ['PBI_USERNAME']
PASSWORD      = os.environ['PBI_PASSWORD']

# ── Constants ─────────────────────────────────────────────────────────────────

TENANT_ID   = 1
RNG         = random.Random(42)
EPOCH       = date(1999, 1, 1)
TODAY       = date.today()
END_DATE    = TODAY
START_DATE  = date(END_DATE.year - 3, END_DATE.month, END_DATE.day)

def dk(d):
    """Date key: days since epoch."""
    return (d - EPOCH).days

NOW_STR = "GETUTCDATE()"   # used in SQL; Python side we use str literal

# ── Master data ───────────────────────────────────────────────────────────────

SITES = [
    {'pk': 1, 'site_id': 'SITE001', 'name': 'Smile Dental – Mayfair',
     'town': 'London', 'postcode': 'W1K 1AA', 'addr1': '14 Brook Street',
     'phone': '020 7946 0001', 'nhs': True},
    {'pk': 2, 'site_id': 'SITE002', 'name': 'Smile Dental – Kensington',
     'town': 'London', 'postcode': 'W8 4PT', 'addr1': '32 Kensington High Street',
     'phone': '020 7946 0002', 'nhs': False},
    {'pk': 3, 'site_id': 'SITE003', 'name': 'Smile Dental – Chelsea',
     'town': 'London', 'postcode': 'SW3 2LX', 'addr1': '8 King\'s Road',
     'phone': '020 7946 0003', 'nhs': True},
]

PRACTITIONERS = [
    # pk, pract_id, first, last, role, site_id, gdc, clinical, daily_hours, revenue_mul
    (1,  1,  'James',     'Wilson',    'Dentist',    'SITE001', 'G100001', True,  7.5, 1.2),
    (2,  2,  'Sarah',     'Mitchell',  'Dentist',    'SITE001', 'G100002', True,  7.0, 1.1),
    (3,  3,  'Emma',      'Clarke',    'Hygienist',  'SITE001', 'G100003', True,  6.0, 0.5),
    (4,  4,  'David',     'Thompson',  'Dentist',    'SITE002', 'G100004', True,  7.5, 1.0),
    (5,  5,  'Rachel',    'Harris',    'Dentist',    'SITE002', 'G100005', True,  6.5, 1.0),
    (6,  6,  'Michael',   'Brown',     'Hygienist',  'SITE002', 'G100006', True,  6.0, 0.5),
    (7,  7,  'Charlotte', 'Davies',    'Dentist',    'SITE003', 'G100007', True,  7.0, 1.0),
    (8,  8,  'Oliver',    'Martin',    'Dentist',    'SITE003', 'G100008', True,  6.5, 0.9),
    (9,  9,  'Grace',     'Johnson',   'Hygienist',  'SITE003', 'G100009', True,  6.0, 0.5),
    (10, 10, 'Thomas',    'Evans',     'Therapist',  'SITE001', 'G100010', True,  5.5, 0.7),
]
# Map site_id → pk
SITE_PK  = {s['site_id']: s['pk'] for s in SITES}
PRACT_BY_SITE = {}
for p in PRACTITIONERS:
    PRACT_BY_SITE.setdefault(p[5], []).append(p)

FIRST_NAMES = ['James','Oliver','William','Harry','Jack','George','Noah','Charlie',
               'Lily','Olivia','Emily','Amelia','Isla','Ava','Sophie','Grace',
               'Thomas','Liam','Ethan','Daniel','Maria','Isabella','Chloe','Hannah']
LAST_NAMES  = ['Smith','Jones','Williams','Taylor','Brown','Davies','Evans','Wilson',
               'Thomas','Roberts','Johnson','Walker','Wright','Clarke','Hall','Green',
               'Wood','Morris','Robinson','Thompson','White','Watson','Jackson','Harris']
TITLES      = ['Mr', 'Mrs', 'Ms', 'Miss', 'Dr']

def random_name(rng):
    first = rng.choice(FIRST_NAMES)
    last  = rng.choice(LAST_NAMES)
    return first, last, f"{first} {last}"

RECALL_MONTHS = [6, 6, 6, 12, 12, 24]

# ── Targets (all_time) ────────────────────────────────────────────────────────
# (metric_key, target_value, variance)
# For % metrics variance is absolute pp; for count/currency it is relative %.
TARGETS = [
    ('total_revenue',             1200000.0, 10.0),
    ('nhs_revenue',                360000.0, 10.0),
    ('private_revenue',            840000.0, 10.0),
    ('revenue_per_patient',           285.0, 10.0),
    ('revenue_per_hour',              150.0, 10.0),
    ('deposit_ratio',                  72.0,  5.0),
    ('new_patients',                  420.0, 10.0),
    ('active_patients',              3500.0,  5.0),
    ('recall_compliance',              82.0,  5.0),
    ('patient_retention',              78.0,  5.0),
    ('recalls_overdue_not_sent',       18.0,  5.0),
    ('retention_outlook',              72.0,  5.0),
    ('acceptance_rate',                65.0,  5.0),
    ('open_courses',                  220.0, 10.0),
    ('open_courses_without_appt',      85.0, 10.0),
    ('open_courses_value',          75000.0, 10.0),
    ('exam_ratio',                     28.0,  3.0),
    ('chair_utilisation',              78.0,  5.0),
    ('dna_rate',                        5.0,  2.0),
    ('days_until_30min_free',           5.0, 10.0),
    ('days_until_1hr_free',             8.0, 10.0),
    ('book_before_you_leave',          72.0,  5.0),
]

# ── FY 2026/27 annual targets ─────────────────────────────────────────────────
# Accumulative metrics only — prorated to a working-day run rate in DAX.
# Period_Value = 'FY 2026/27' (matches Date Grouping without the "(YTD)" suffix).
FY_TARGETS_2627 = [
    ('total_revenue',    1200000.0, 10.0),
    ('nhs_revenue',       360000.0, 10.0),
    ('private_revenue',   840000.0, 10.0),
    ('new_patients',         420.0, 10.0),
    ('nhs_udas',            2800.0, 10.0),
    ('nhs_uoas',             150.0, 10.0),
]

# ── Connection ────────────────────────────────────────────────────────────────

def connect():
    conn_str = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={FABRIC_SERVER},1433;"
        f"Database={FABRIC_DB};"
        f"Authentication=ActiveDirectoryPassword;"
        f"UID={USERNAME};PWD={PASSWORD};"
        f"Encrypt=yes;TrustServerCertificate=no;"
    )
    conn = pyodbc.connect(conn_str)
    conn.autocommit = True
    return conn

def ex(cur, sql, params=None):
    cur.execute(sql, params or [])

def exmany(cur, sql, rows, batch=500):
    cur.fast_executemany = True
    for i in range(0, len(rows), batch):
        try:
            cur.executemany(sql, rows[i:i+batch])
        except pyodbc.Error as e:
            # Fabric returns 01000 info/trace messages that pyodbc surfaces as exceptions
            if e.args[0] != '01000':
                raise
        print(f"    … {min(i+batch, len(rows)):,}/{len(rows):,}", flush=True)


def fresh(fn, *args, **kwargs):
    """Call fn with a fresh connection + cursor; closes on exit."""
    conn = connect()
    cur  = conn.cursor()
    try:
        fn(cur, *args, **kwargs)
    finally:
        conn.close()

# ── Delete existing test data ─────────────────────────────────────────────────

def delete_existing(cur):
    print("  Deleting existing Tenant_ID=1 data …")
    for tbl in [
        'Gold.Fact_Invoice_Items',
        'Gold.Fact_Recalls',
        'Gold.Aggregate_Site_Patient_Practitioner_Daily',
        'Gold.Aggregate_Site_Patient_Current',
        'Gold.Aggregate_Site_Practitioner_Current',
        'Gold.Dim_Treatment_Plans',
        'Gold.Dim_Patients',
        'Gold.Dim_Practitioners',
        'Gold.Dim_Practice_Sites',
        'Gold.Dim_Tenants',
    ]:
        ex(cur, f"DELETE FROM {tbl} WHERE Tenant_ID = ?", [TENANT_ID])
    ex(cur,
       "DELETE FROM Input.Targets "
       "WHERE Tenant_ID = ? AND Site_ID IS NULL AND Practitioner_ID IS NULL",
       [TENANT_ID])
    print("  Done.")

# ── Dim_Tenants ───────────────────────────────────────────────────────────────

def seed_tenants(cur):
    print("  Dim_Tenants …")
    ex(cur,
       "INSERT INTO Gold.Dim_Tenants (pk_Tenant,Tenant_ID,Tenant_Name,Is_Active,"
       "DW_Created_At,DW_Updated_At) VALUES (?,?,?,?,GETUTCDATE(),GETUTCDATE())",
       [1, TENANT_ID, 'Smile Dental Group', 1])

# ── Dim_Practice_Sites ────────────────────────────────────────────────────────

def seed_sites(cur):
    print("  Dim_Practice_Sites …")
    rows = []
    for s in SITES:
        rows.append((
            s['pk'], TENANT_ID, s['site_id'], s['name'], 1,
            s['addr1'], None, s['town'], s['postcode'], s['phone'],
            None, None, None,
            dtime(8,30), dtime(17,30), dtime(8,30), dtime(17,30), dtime(8,30), dtime(17,30),
            dtime(8,30), dtime(17,30), dtime(8,30), dtime(17,0),
            str(s['pk']), 'Smile Dental Group',
            s['addr1'], None, s['town'], s['postcode'], s['phone'],
            'info@smiledental.co.uk', 'https://smiledental.co.uk',
            1 if s['nhs'] else 0, 'Europe/London',
        ))
    exmany(cur,
        "INSERT INTO Gold.Dim_Practice_Sites ("
        "pk_Practice_Site,Tenant_ID,Site_ID,Site_Name,Site_Active,"
        "Site_Address_Line_1,Site_Address_Line_2,Site_Town,Site_Postcode,Site_Phone,"
        "Site_Website,Site_Logo_URL,Site_Default_Payment_Plan_ID,"
        "Mon_Open,Mon_Close,Tue_Open,Tue_Close,Wed_Open,Wed_Close,"
        "Thu_Open,Thu_Close,Fri_Open,Fri_Close,"
        "Practice_ID,Practice_Name,"
        "Practice_Address_Line_1,Practice_Address_Line_2,Practice_Town,Practice_Postcode,"
        "Practice_Phone,Practice_Email,Practice_Website,Practice_NHS,Practice_Time_Zone,"
        "DW_Created_At,DW_Updated_At) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,GETUTCDATE(),GETUTCDATE())",
        rows)

# ── Dim_Practitioners ─────────────────────────────────────────────────────────

def seed_practitioners(cur):
    print("  Dim_Practitioners …")
    rows = []
    for p in PRACTITIONERS:
        pk,pid,first,last,role,site_id,gdc,_,_,_ = p
        rows.append((
            1_000_000 + pk, TENANT_ID, pid, None, 'Dr', first, None, last, f"Dr {first} {last}",
            f"{first.lower()}.{last.lower()}@smiledental.co.uk", None,
            role, 3, 1, None, gdc, None, site_id, None, None, None, None,
        ))
    exmany(cur,
        "INSERT INTO Gold.Dim_Practitioners ("
        "pk_Practitioner,Tenant_ID,Practitioner_ID,User_ID,Title,First_Name,Middle_Name,"
        "Last_Name,Full_Name,Email,Mobile_Phone,Role,Permission_Level,Active,Colour,"
        "GDC_Number,NHS_Number,Site_ID,Default_Contract_ID,Contract_Targets_String,"
        "Image_URL,Last_Login_Date,DW_Created_At,DW_Updated_At) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,GETUTCDATE(),GETUTCDATE())",
        rows)

# ── Dim_Patients ──────────────────────────────────────────────────────────────

N_PATIENTS = 1200

def build_patients():
    """Returns list of patient dicts with lifecycle attributes."""
    patients = []
    for i in range(N_PATIENTS):
        pid   = i + 1
        first, last, full = random_name(RNG)
        # Spread registration dates over 4 years (a year before START_DATE)
        reg_offset = RNG.randint(0, (END_DATE - date(START_DATE.year - 1, 1, 1)).days)
        reg_date   = date(START_DATE.year - 1, 1, 1) + timedelta(days=reg_offset)
        # Assign to site + practitioner
        site    = RNG.choice(SITES)
        site_id = site['site_id']
        # Primary dentist from same site
        dentists = [p for p in PRACT_BY_SITE.get(site_id, []) if p[3] == 'Dentist']
        if not dentists:
            dentists = PRACTITIONERS[:4]
        prim = RNG.choice(dentists)
        recall_interval = RNG.choice(RECALL_MONTHS)
        age = RNG.randint(18, 85)
        dob = TODAY.replace(year=TODAY.year - age)
        active = RNG.random() < 0.72   # ~72% active (850/1200)
        patients.append({
            'pk':               1_000_000 + pid,
            'patient_id':       pid,
            'first':            first,
            'last':             last,
            'full':             full,
            'title':            RNG.choice(TITLES),
            'dob':              dob,
            'age':              age,
            'site_id':          site_id,
            'site_pk':          site['pk'],
            'prim_pract_pk':    prim[0],
            'prim_pract_id':    prim[1],
            'recall_interval':  recall_interval,
            'recall_due':       None,
            'active':           active,
            'reg_date':         reg_date,
            'first_appt_date':  None,
            'last_appt_date':   None,
            'next_appt_date':   None,
            'total_revenue':    0.0,
            'appointments':     [],   # list of (date, practitioner_pk, site_pk, revenue, is_exam, is_dna, is_bbyl, hours)
        })
    return patients

# ── Generate appointments ─────────────────────────────────────────────────────

DNA_RATE   = 0.05
EXAM_RATIO = 0.28
BBYL_RATE  = 0.80

def lognormal_revenue(rng, is_exam, pract_revenue_mul):
    """Log-normal appointment revenue. Exam appointments are shorter/cheaper."""
    if is_exam:
        mu, sigma = math.log(65), 0.35   # median £65, range £35-£150
    else:
        mu, sigma = math.log(190), 0.55  # median £190, range £60-£800
    val = math.exp(mu + sigma * rng.gauss(0, 1))
    return round(max(15.0, val) * pract_revenue_mul, 2)

def appointment_hours(rng, is_exam):
    if is_exam:
        return round(rng.uniform(0.33, 0.75), 2)   # 20-45 min
    return round(rng.uniform(0.5, 1.5), 2)          # 30-90 min

def working_days(start, end):
    """All Mon-Fri between start and end inclusive."""
    d = start
    while d <= end:
        if d.weekday() < 5:   # Mon=0 … Fri=4
            yield d
        d += timedelta(days=1)

def generate_appointments(patients):
    """
    Fills each patient's appointments list with tuples:
      (date, pract_pk, site_pk, revenue, is_exam, is_dna, is_bbyl, worked_hours, appt_hours)
    """
    # Build patient lookup by site
    by_site = {}
    for pt in patients:
        by_site.setdefault(pt['site_pk'], []).append(pt)

    # For each working day, each practitioner sees some patients
    new_patient_set = set()
    for day in working_days(START_DATE, END_DATE):
        for pdata in PRACTITIONERS:
            pk,pid,first,last,role,site_id,gdc,clinical,daily_hours,rev_mul = pdata
            site_pk = SITE_PK[site_id]
            # Practitioner works this day? ~75% of working days
            if not clinical or RNG.random() > 0.75:
                continue
            # Patients seen today by this practitioner
            n_pts = RNG.randint(4, 9) if role == 'Dentist' else RNG.randint(6, 12)
            site_patients = by_site.get(site_pk, [])
            if not site_patients:
                continue
            sample = RNG.sample(site_patients, min(n_pts, len(site_patients)))
            for pt in sample:
                if pt['reg_date'] > day:
                    continue
                is_dna  = RNG.random() < DNA_RATE
                is_exam = RNG.random() < EXAM_RATIO
                rev     = 0.0 if is_dna else lognormal_revenue(RNG, is_exam, rev_mul)
                ahrs    = appointment_hours(RNG, is_exam)
                whrs    = daily_hours
                is_bbyl = (not is_dna) and RNG.random() < BBYL_RATE
                is_new  = pt['pk'] not in new_patient_set
                if is_new:
                    new_patient_set.add(pt['pk'])
                pt['appointments'].append((day, 1_000_000 + pk, site_pk, rev, is_exam, is_dna, is_bbyl, whrs, ahrs, is_new))
                pt['total_revenue'] += rev

    # Compute lifecycle dates
    for pt in patients:
        if pt['appointments']:
            dates = [a[0] for a in pt['appointments']]
            pt['first_appt_date'] = min(dates)
            pt['last_appt_date']  = max(dates)
            # Next appointment: last date + recall interval (if in future)
            next_d = pt['last_appt_date'] + timedelta(days=pt['recall_interval'] * 30)
            pt['next_appt_date'] = next_d if next_d > TODAY else None
            # Recall due date: last appointment + recall interval
            pt['recall_due'] = pt['last_appt_date'] + timedelta(days=pt['recall_interval'] * 30)

    return patients

# ── Insert Dim_Patients ───────────────────────────────────────────────────────

def seed_patients(cur, patients):
    print(f"  Dim_Patients ({len(patients)} rows) …")
    rows = []
    for pt in patients:
        rows.append((
            pt['pk'], TENANT_ID, pt['patient_id'], None,              # 4  pk–account_id
            pt['title'], pt['first'], None, pt['last'], None, pt['full'],  # 6  title–full_name
            pt['dob'], pt['age'],                                     # 2  dob, age
            None, None, None, None, None,                             # 5  gender–ni_number
            None, None, None, None,                                   # 4  email–work_phone
            1 if pt['active'] else 0, 0, None, None, pt['site_id'], None,  # 6  active–family_id
            None, pt['prim_pract_id'], None,                          # 3  acq_src–hyg_pract_id
            None, None, None, None,                                   # 4  dentist_recall–hyg_recall_interval
            'sms', None, 1, 1, 'accepted',                           # 5  recall_method–marketing_consent
            None, None, None, None,                                   # 4  occupation–custom_field_2
            pt['first_appt_date'], pt['last_appt_date'], pt['next_appt_date'],  # 3
            None, None, None,                                         # 3  first_exam–next_exam
            None, None,                                               # 2  last_scale, next_scale
            None, None,                                               # 2  last_fta, last_cancelled
            round(pt['total_revenue'], 4), round(pt['total_revenue'] * 1.05, 4),  # 2
            None, pt['reg_date'], None,                               # 3  nhs_exemption–patient_updated
        ))                                                            # = 58 params
    exmany(cur,
        "INSERT INTO Gold.Dim_Patients ("
        "pk_Patient,Tenant_ID,Patient_ID,Account_ID,"
        "Title,First_Name,Middle_Name,Last_Name,Preferred_Name,Full_Name,"
        "Date_Of_Birth,Age_Years,"
        "Gender_Code,Gender_Description,Ethnicity_Code,NHS_Number,NI_Number,"
        "Email_Address,Home_Phone,Mobile_Phone,Work_Phone,"
        "Active,Medical_Alert,Medical_Alert_Text,Payment_Plan_ID,Site_ID,Family_ID,"
        "Acquisition_Source_ID,Dentist_Practitioner_ID,Hygienist_Practitioner_ID,"
        "Dentist_Recall_Date,Dentist_Recall_Interval_Months,"
        "Hygienist_Recall_Date,Hygienist_Recall_Interval_Months,"
        "Recall_Method,Preferred_Contact_Method,Use_Email,Use_SMS,Marketing_Consent,"
        "Occupation,Legacy_ID,Custom_Field_1,Custom_Field_2,"
        "First_Appointment_Date,Last_Appointment_Date,Next_Appointment_Date,"
        "First_Exam_Date,Last_Exam_Date,Next_Exam_Date,"
        "Last_Scale_Polish_Date,Next_Scale_Polish_Date,"
        "Last_FTA_Date,Last_Cancelled_Appointment_Date,"
        "Total_Paid,Total_Invoiced,"
        "NHS_Exemption_Code,Patient_Created_Date,Patient_Updated_Date,"
        "DW_Created_At,DW_Updated_At) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,"
        "?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,GETUTCDATE(),GETUTCDATE())",
        rows)

# ── Aggregate_Site_Patient_Practitioner_Daily ─────────────────────────────────

def seed_daily(cur, patients, resume_from_pk=0):
    """One row per (site, patient, practitioner, date) appointment."""
    print("  Aggregate_Site_Patient_Practitioner_Daily …")
    rows = []
    pk = 1
    for pt in patients:
        for appt in pt['appointments']:
            day, pract_pk, site_pk, rev, is_exam, is_dna, is_bbyl, whrs, ahrs, is_new = appt
            if pk > resume_from_pk:
                is_nhs_site = site_pk in (1, 3)
                nhs_rev  = rev * 0.3 if is_nhs_site else 0.0
                priv_rev = rev - nhs_rev
                rows.append((
                    pk, site_pk, pt['pk'], pract_pk, dk(day), TENANT_ID,
                    round(0.8, 2) if (is_nhs_site and not is_dna) else 0.0,
                    0.0, 1,
                    1 if is_dna else 0,
                    1 if is_bbyl else 0,
                    round(nhs_rev, 2), round(priv_rev, 2),
                    1 if pt.get('has_open_plan') else 0,
                    1 if (pt['next_appt_date'] and pt['next_appt_date'] > day) else 0,
                    1 if is_exam else 0,
                    1 if (not is_exam and not is_dna) else 0,
                    1 if is_new else 0,
                    round(whrs, 2),
                    0.0 if is_dna else round(ahrs, 2),
                ))
            pk += 1
    print(f"    {len(rows):,} rows to insert (skipping first {resume_from_pk:,}) …")
    exmany(cur,
        "INSERT INTO Gold.Aggregate_Site_Patient_Practitioner_Daily ("
        "pk_Site_Patient_Practitioner_Daily,fk_Site,fk_Patient,fk_Practitioner,fk_Date,Tenant_ID,"
        "NHS_UDAs,NHS_UOAs,Appointments,DNA_Appointments,BBYL_Appointments,"
        "NHS_Revenue,Private_Revenue,Open_Treatment_Plan,Future_Appointment,"
        "Exam_Count,Treatment_Count,New_Patient,Worked_Hours,Appointment_Hours,"
        "DW_Created_At,DW_Updated_At) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,GETUTCDATE(),GETUTCDATE())",
        rows)

# ── Build treatment plans (in-memory) ────────────────────────────────────────

def build_treatment_plans(patients):
    """Adds treatment_plans list and has_open_plan flag to each patient dict."""
    ACCEPTANCE_RATE = 0.65
    COMPLETION_RATE = 0.80
    plan_pk = 1_000_000
    plan_id = 0

    for pt in patients:
        pt['treatment_plans'] = []
        pt['has_open_plan']   = False

        appt_dates = sorted(a[0] for a in pt['appointments'])
        if not appt_dates:
            continue

        months_history = max(1, (TODAY - appt_dates[0]).days // 30)
        n_plans = RNG.randint(1, min(3, max(1, months_history // 10)))

        for i in range(n_plans):
            plan_pk += 1
            plan_id += 1

            idx          = min(int(len(appt_dates) * i / max(n_plans, 1)), len(appt_dates) - 1)
            created_date = appt_dates[idx]

            accepted   = RNG.random() < ACCEPTANCE_RATE
            start_date = created_date + timedelta(days=RNG.randint(0, 7)) if accepted else None

            completed      = False
            completed_date = None
            if accepted and start_date:
                completed = RNG.random() < COMPLETION_RATE
                if completed:
                    comp_d = start_date + timedelta(days=RNG.randint(60, 180))
                    if comp_d > TODAY:
                        completed = False
                    else:
                        completed_date = datetime(comp_d.year, comp_d.month, comp_d.day)

            is_nhs = pt['site_pk'] in (1, 3)
            if is_nhs and accepted:
                band    = RNG.choices([1, 2, 3], weights=[30, 50, 20])[0]
                nhs_uda = {1: 1.0, 2: 3.0, 3: 12.0}[band]
                nhs_done = nhs_uda if completed else round(nhs_uda * RNG.uniform(0, 0.7), 1)
            else:
                nhs_uda  = 0.0
                nhs_done = 0.0

            priv_val = round(math.exp(math.log(350) + 0.7 * RNG.gauss(0, 1)), 2) if accepted else 0.0

            pt['treatment_plans'].append({
                'pk':            plan_pk,
                'plan_id':       plan_id,
                'patient_id':    pt['patient_id'],
                'practitioner_id': pt['prim_pract_id'],
                'completed':     completed,
                'start_date':    start_date,
                'completed_date': completed_date,
                'nhs_uda':       nhs_uda,
                'nhs_done':      nhs_done,
                'priv_val':      priv_val,
                'created_dt':    datetime(created_date.year, created_date.month, created_date.day),
            })

            if accepted and not completed:
                pt['has_open_plan'] = True

# ── Aggregate_Site_Patient_Current ────────────────────────────────────────────

def seed_patient_current(cur, patients):
    print("  Aggregate_Site_Patient_Current …")
    rows = []
    cutoff_active   = TODAY - timedelta(days=730)   # 2 years
    cutoff_retained = TODAY - timedelta(days=365)
    for pk_idx, pt in enumerate(patients):
        recall_due  = pt.get('recall_due')
        last_appt   = pt['last_appt_date']
        active_bit  = 1 if (last_appt and last_appt >= cutoff_active) else 0
        retained    = 1 if (last_appt and last_appt >= cutoff_retained) else 0
        recall_due_bit  = 1 if (recall_due and recall_due <= TODAY) else 0
        recall_sent_bit = 1 if (recall_due_bit and RNG.random() < 0.82) else 0
        future_apt  = 1 if (pt['next_appt_date'] and pt['next_appt_date'] > TODAY) else 0
        rows.append((
            pk_idx + 1, pt['site_pk'], pt['pk'], TENANT_ID,
            retained, active_bit, recall_due_bit, recall_sent_bit, future_apt,
        ))
    exmany(cur,
        "INSERT INTO Gold.Aggregate_Site_Patient_Current ("
        "pk_Site_Patient_Current,fk_Site,fk_Patient,Tenant_ID,"
        "Retained_Patients,Active_Patients,Recall_Due,Recall_Sent,Future_Appointment,"
        "DW_Created_At,DW_Updated_At) "
        "VALUES (?,?,?,?,?,?,?,?,?,GETUTCDATE(),GETUTCDATE())",
        rows)

# ── Aggregate_Site_Practitioner_Current ──────────────────────────────────────

def seed_practitioner_current(cur):
    print("  Aggregate_Site_Practitioner_Current …")
    rows = []
    for idx, p in enumerate(PRACTITIONERS):
        pk,pid,_,_,_,site_id,_,_,_,_ = p
        site_pk = SITE_PK[site_id]
        days30 = RNG.randint(2, 9)
        days60 = days30 + RNG.randint(1, 5)
        rows.append((idx + 1, site_pk, 1_000_000 + pk, TENANT_ID, days30, days60))
    exmany(cur,
        "INSERT INTO Gold.Aggregate_Site_Practitioner_Current ("
        "pk_Site_Practitioner_Current,fk_Site,fk_Practitioner,Tenant_ID,"
        "Days_Until_Next_30_Mins,Days_Until_Next_1_Hour_Free,"
        "DW_Created_At,DW_Updated_At) "
        "VALUES (?,?,?,?,?,?,GETUTCDATE(),GETUTCDATE())",
        rows)

# ── Fact_Recalls ──────────────────────────────────────────────────────────────

def seed_recalls(cur, patients, resume=False):
    print("  Fact_Recalls …")
    if resume:
        cur.execute(
            "SELECT COUNT(*) FROM Gold.Fact_Recalls WHERE Tenant_ID = ?", [TENANT_ID])
        already = int(cur.fetchone()[0])
        if already > 0:
            print(f"    already has {already:,} rows, skipping.")
            return
    rows = []
    for pt in patients:
        if not pt['recall_due']:
            continue
        # One recall per recall interval back through their history
        due = pt['recall_due']
        bk  = 1
        # Generate recalls going back as far as reg_date
        while due >= pt['reg_date'] + timedelta(days=60):
            days_overdue = max(0, (TODAY - due).days)
            if days_overdue > 0:
                status = RNG.choice(['attended', 'attended', 'attended', 'overdue', 'cancelled'])
            else:
                status = 'pending'
            rows.append((
                TENANT_ID,
                f"REC-{pt['patient_id']:05d}-{bk}",
                pt['pk'],
                dk(due),
                dk(due - timedelta(days=3)),  # fk_Date_Run
                None, None, None,             # reminder date keys
                None,                         # Appointment_ID
                'Dentist',                    # Recall_Type
                'sms',                        # Recall_Method
                status,
                None,                         # Workflow_Status
                None,                         # Workflow_Stage_ID
                'sms', None, 'sms',           # reminder types
                1 if status != 'pending' else 0,
                due,                          # Due_Date
                due - timedelta(days=3),      # Run_Date
                days_overdue,
            ))
            due = due - timedelta(days=pt['recall_interval'] * 30)
            bk += 1
    print(f"    {len(rows):,} rows …")
    exmany(cur,
        "INSERT INTO Gold.Fact_Recalls ("
        "Tenant_ID,bk_Recall_ID,fk_Patient,fk_Date_Due,fk_Date_Run,"
        "fk_Date_First_Reminder,fk_Date_Second_Reminder,fk_Date_Last_Reminded,"
        "Appointment_ID,Recall_Type,Recall_Method,Status,Workflow_Status,"
        "Workflow_Stage_ID,First_Reminder_Type,Second_Reminder_Type,Latest_Reminder_Type,"
        "Times_Contacted,Due_Date,Run_Date,Days_Overdue,"
        "DW_Created_At,DW_Updated_At) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,GETUTCDATE(),GETUTCDATE())",
        rows)

# ── Gold.Dim_Treatment_Plans ──────────────────────────────────────────────────

def seed_treatment_plans(cur, patients):
    print("  Gold.Dim_Treatment_Plans …")
    rows = []
    for pt in patients:
        for p in pt.get('treatment_plans', []):
            cd = p['completed_date']
            rows.append((
                p['pk'], TENANT_ID, p['plan_id'], None,
                p['patient_id'], p['practitioner_id'],
                1 if p['completed'] else 0,
                p['start_date'],
                cd.date() if cd else None,   # End_Date
                cd,                           # Completed_Date  datetime2(3)
                cd.date() if cd else None,   # Last_Completed_Date
                p['nhs_uda'], p['nhs_done'], p['priv_val'],
                p['created_dt'], p['created_dt'],
            ))
    print(f"    {len(rows):,} rows …")
    exmany(cur,
        "INSERT INTO Gold.Dim_Treatment_Plans ("
        "pk_Treatment_Plan,Tenant_ID,Treatment_Plan_ID,Nickname,"
        "Patient_ID,Practitioner_ID,Completed,Start_Date,End_Date,"
        "Completed_Date,Last_Completed_Date,"
        "NHS_UDA_Value,NHS_Completed_UDA_Value,Private_Treatment_Value,"
        "Created_Date,Updated_Date,"
        "DW_Created_At,DW_Updated_At) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,GETUTCDATE(),GETUTCDATE())",
        rows)

# ── Gold.Fact_Invoice_Items ───────────────────────────────────────────────────

def seed_invoice_items(cur, patients):
    print("  Gold.Fact_Invoice_Items …")
    rows = []
    inv_id = 10_000
    for pt in patients:
        for appt in pt['appointments']:
            day, pract_pk, site_pk, rev, is_exam, is_dna, is_bbyl, whrs, ahrs, is_new = appt
            if is_dna:
                continue
            inv_id += 1
            is_nhs      = site_pk in (1, 3)
            nhs_charge  = round(rev * 0.3, 2) if is_nhs else 0.0
            paid        = RNG.random() < 0.90
            paid_date   = day + timedelta(days=RNG.randint(1, 30)) if paid else None
            outstanding = 0.0 if paid else round(rev, 2)
            item_name   = 'Dental Examination' if is_exam else 'Dental Treatment'
            rows.append((
                TENANT_ID,
                f'INV{inv_id:07d}',
                pt['pk'], pract_pk,
                None, None, None, site_pk, None,
                dk(day),
                dk(day + timedelta(days=30)),
                dk(paid_date) if paid_date else None,
                dk(day),
                inv_id, None, None, item_name,
                inv_id, 'Due on receipt', None,
                1 if paid else 0,
                round(rev, 2), 1.0, round(rev, 2),
                nhs_charge, round(rev, 2), outstanding, nhs_charge,
            ))
    print(f"    {len(rows):,} rows …")
    exmany(cur,
        "INSERT INTO Gold.Fact_Invoice_Items ("
        "Tenant_ID,bk_Invoice_Item_ID,fk_Patient,fk_Practitioner,"
        "fk_Payment_Plan,fk_Treatment_Plan,fk_Account,fk_Practice_Site,fk_User,"
        "fk_Date_Invoice,fk_Date_Due,fk_Date_Paid,fk_Date_Created,"
        "Invoice_ID,Treatment_Plan_Item_ID,Sundry_ID,Item_Name,"
        "Invoice_Reference,Invoice_Payment_Terms,Invoice_Footnote,"
        "Invoice_Paid,Item_Price,Quantity,Total_Price,"
        "NHS_Charge,Invoice_Amount,Invoice_Amount_Outstanding,Invoice_NHS_Amount,"
        "DW_Created_At,DW_Updated_At) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,GETUTCDATE(),GETUTCDATE())",
        rows)

# ── Input.Targets ─────────────────────────────────────────────────────────────

def seed_targets(cur):
    print("  Input.Targets …")
    all_time = [(TENANT_ID, None, None, m, 'all_time', 'all', t, v)
                for m, t, v in TARGETS]
    annual   = [(TENANT_ID, None, None, m, 'annual', 'FY 2026/27', t, v)
                for m, t, v in FY_TARGETS_2627]
    exmany(cur,
        "INSERT INTO Input.Targets "
        "(Tenant_ID,Site_ID,Practitioner_ID,Metric,Period_Type,Period_Value,"
        "Target_Value,Variance,DW_Created_At,DW_Updated_At) "
        "VALUES (?,?,?,?,?,?,?,?,GETUTCDATE(),GETUTCDATE())",
        all_time + annual)

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--resume', action='store_true',
                        help='Skip delete/dims; resume daily aggregate from last committed pk')
    args = parser.parse_args()

    print(f"Connecting to {FABRIC_DB} @ {FABRIC_SERVER} …")
    conn = connect()
    cur  = conn.cursor()

    print("Building patient + appointment data (no DB calls) …")
    patients = build_patients()
    patients = generate_appointments(patients)
    build_treatment_plans(patients)
    total_apts  = sum(len(p['appointments']) for p in patients)
    total_rev   = sum(p['total_revenue'] for p in patients)
    active_cnt  = sum(1 for p in patients if p['active'])
    open_plan_cnt = sum(1 for p in patients if p['has_open_plan'])
    total_plans = sum(len(p['treatment_plans']) for p in patients)
    print(f"  {len(patients)} patients, {active_cnt} active, {open_plan_cnt} with open plans")
    print(f"  {total_apts:,} appointment rows | £{total_rev:,.0f} total revenue")
    print(f"  {total_plans:,} treatment plans")

    print("\nSeeding …")
    if args.resume:
        conn2 = connect()
        cur2  = conn2.cursor()
        cur2.execute(
            "SELECT ISNULL(MAX(pk_Site_Patient_Practitioner_Daily), 0) "
            "FROM Gold.Aggregate_Site_Patient_Practitioner_Daily WHERE Tenant_ID = ?",
            [TENANT_ID])
        resume_from_pk = int(cur2.fetchone()[0])
        conn2.close()
        print(f"  --resume: daily aggregate at {resume_from_pk:,} rows, continuing …")
    else:
        resume_from_pk = 0
        fresh(delete_existing)
        fresh(seed_tenants)
        fresh(seed_sites)
        fresh(seed_practitioners)
        fresh(seed_patients, patients)

    fresh(seed_daily, patients, resume_from_pk=resume_from_pk)
    fresh(seed_patient_current, patients)
    fresh(seed_practitioner_current)
    fresh(seed_recalls, patients, resume=args.resume)
    fresh(seed_treatment_plans, patients)
    fresh(seed_invoice_items, patients)
    fresh(seed_targets)

    conn.close()
    print("\nDone.")

if __name__ == '__main__':
    main()
