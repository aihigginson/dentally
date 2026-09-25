"""Seed tenant definitions and their synthetic Xero finance, shared by both seeders.

Lifted out of seed_onelake.py so the Bronze seeder can reach them without importing pandas,
pyarrow and deltalake -- which seed_onelake needs only to write Delta into the lakehouse, and
which the Bronze path (plain pyodbc INSERTs) does not.

One definition, two destinations. Duplicating a 200-line practice definition would guarantee the
two seeders drifted into describing different practices.
"""
import random
from collections import defaultdict
from datetime import date, datetime, timedelta

from generate_data import _u5, _pp, _sundry, _wl, _acq, _cr, _contract


def generate_xero_finance(tdef, data, load_ts):
    tid  = tdef['tenant_id']
    xtid = _u5(tid, 'xero_tenant')
    rng  = random.Random(1000 + tid)

    coa = [  # (code, name, type, class)
        ('090', 'Business Bank Account',    'BANK',        'ASSET'),
        ('200', 'Patient Income - NHS',     'SALES',       'REVENUE'),
        ('201', 'Patient Income - Private', 'SALES',       'REVENUE'),
        ('202', 'Plan Income',              'SALES',       'REVENUE'),
        ('300', 'Laboratory Fees',          'DIRECTCOSTS', 'EXPENSE'),
        ('310', 'Dental Materials',         'DIRECTCOSTS', 'EXPENSE'),
        ('320', 'Associate Fees',           'DIRECTCOSTS', 'EXPENSE'),
        ('400', 'Staff Salaries',           'OVERHEADS',   'EXPENSE'),
        ('410', 'Rent',                     'OVERHEADS',   'EXPENSE'),
        ('420', 'Business Rates',           'OVERHEADS',   'EXPENSE'),
        ('430', 'Light, Power, Heating',    'OVERHEADS',   'EXPENSE'),
        ('440', 'Equipment Lease',          'OVERHEADS',   'EXPENSE'),
        ('450', 'Advertising & Marketing',  'OVERHEADS',   'EXPENSE'),
        ('460', 'Insurance',                'OVERHEADS',   'EXPENSE'),
        ('470', 'Software & IT',            'OVERHEADS',   'EXPENSE'),
        ('480', 'Repairs & Maintenance',    'OVERHEADS',   'EXPENSE'),
        ('490', 'Professional Fees',        'OVERHEADS',   'EXPENSE'),
        ('495', 'General Expenses',         'OVERHEADS',   'EXPENSE'),
        ('500', 'Depreciation',             'DEPRECIATN',  'EXPENSE'),  # excluded from EBITDA (D&A)
        ('510', 'Loan Interest',            'OVERHEADS',   'EXPENSE'),  # excluded from EBITDA (interest)
    ]
    name_by_code = {c: n for c, n, _, _ in coa}
    accounts = [{
        'Tenant_ID': str(tid), 'Xero_Tenant_ID': xtid,
        'Account_ID': _u5(tid, 'xero_acct', code), 'Code': code, 'Name': name,
        'Type': typ, 'Class': cls, 'Reporting_Code': None, 'Reporting_Code_Name': None,
        'Status': 'ACTIVE', 'DW_Stage_Loaded_At': load_ts,
    } for code, name, typ, cls in coa]

    # Org registry row (org -> Tenant_ID + default site) and a single "Site" tracking
    # category, so the V038 Xero stage schema is complete (single-site synthetic tenant:
    # lines carry no tracking, so Fact_Finance resolves site via this org default).
    site = (data.get('sites') or [{}])[0]
    org = {
        'Tenant_ID': str(tid), 'Xero_Tenant_ID': xtid,
        'Tenant_Name': tdef['practice']['name'],
        'Default_Site_ID': site.get('id'), 'DW_Stage_Loaded_At': load_ts,
    }
    tracking = [{
        'Tenant_ID': str(tid), 'Xero_Tenant_ID': xtid,
        'Tracking_Category_ID': _u5(tid, 'xero_trackcat', 'site'),
        'Category_Name': 'Site', 'Category_Status': 'ACTIVE',
        'Tracking_Option_ID': _u5(tid, 'xero_trackopt', 'site'),
        'Option_Name': site.get('name'), 'Option_Status': 'ACTIVE',
        'DW_Stage_Loaded_At': load_ts,
    }]

    # Monthly Dentally revenue (YYYY-MM -> total invoiced)
    rev_by_month = defaultdict(float)
    for inv in data['invoices']:
        d, amt = inv.get('dated_on'), float(inv.get('amount') or 0)
        if d and amt > 0:
            rev_by_month[str(d)[:7]] += amt
    if not rev_by_month:
        return accounts, [], org, tracking
    avg_rev = sum(rev_by_month.values()) / len(rev_by_month)

    inc = {'200': 0.55, '201': 0.35, '202': 0.10} if tdef.get('nhs') \
          else {'200': 0.05, '201': 0.85, '202': 0.10}
    var_cost = {'320': 0.34, '300': 0.07, '310': 0.05, '400': 0.17,
                '430': 0.018, '450': 0.02, '480': 0.01, '495': 0.012}
    fixed_amt = {c: round(avg_rev * f, 2) for c, f in
                 {'410': 0.055, '420': 0.012, '440': 0.02, '460': 0.009,
                  '470': 0.011, '490': 0.006,
                  '500': 0.03, '510': 0.015}.items()}  # depreciation + interest (below EBITDA)

    lines = []
    def add(month, code, doc_type, amount):
        if not amount or amount <= 0:
            return
        doc_id = _u5(tid, 'xero_doc', code, month)
        lines.append({
            'Tenant_ID': str(tid), 'Xero_Tenant_ID': xtid, 'Source': 'INVOICE',
            'Doc_ID': doc_id, 'Doc_Number': None, 'Doc_Type': doc_type, 'Doc_Status': 'AUTHORISED',
            'Doc_Date': f'{month}-15', 'Contact_Name': None, 'Line_Amount_Types': 'NoTax',
            'Line_Item_ID': _u5(doc_id, 'line'), 'Account_Code': code,
            'Account_ID': _u5(tid, 'xero_acct', code), 'Description': name_by_code[code],
            'Line_Amount': round(amount, 2), 'Tax_Amount': 0, 'Tracking': [],
            'Tracking_Cat_1': None, 'Tracking_Opt_1': None,
            'Tracking_Cat_2': None, 'Tracking_Opt_2': None,
            'DW_Stage_Loaded_At': load_ts,
        })

    for month in sorted(rev_by_month):
        rev = rev_by_month[month]
        for code, frac in inc.items():
            add(month, code, 'ACCREC', rev * frac)
        for code, frac in var_cost.items():
            add(month, code, 'ACCPAY', rev * frac * rng.uniform(0.92, 1.08))
        for code, amt in fixed_amt.items():
            add(month, code, 'ACCPAY', amt)
    return accounts, lines, org, tracking


# ── Tenant definitions (matches notebook) ─────────────────────────────────────

T11 = {
    'tenant_id': 11, 'nhs': True, 'has_ortho': False, 'price_mult': 1.0, 'n_patients': 4000,
    'domain': 'valleydental.co.uk',
    'practice': {
        'id': _u5('practice', 11), 'name': 'Valley Dental Group', 'nhs': True,
        'address_line_1': '22 Queen Square', 'address_line_2': None,
        'town': 'Bristol', 'postcode': 'BS1 4NH',
        'phone_number': '0117 123 0001', 'email_address': 'info@valleydental.co.uk',
        'patient_email_address': 'patients@valleydental.co.uk',
        'website': 'https://valleydental.co.uk', 'logo_url': None,
        'slug': 'valley-dental', 'time_zone': 'Europe/London',
        'medical_history_expiry_days': 365,
        'custom_patient_field_label_1': None, 'custom_patient_field_label_2': None,
        'oh_mon_open': '09:00', 'oh_mon_close': '17:30',
        'oh_tues_open': '09:00', 'oh_tues_close': '17:30',
        'oh_wed_open': '09:00', 'oh_wed_close': '17:30',
        'oh_thur_open': '09:00', 'oh_thur_close': '17:30',
        'oh_fri_open': '09:00', 'oh_fri_close': '17:30',
        'oh_sat_open': None, 'oh_sat_close': None,
        'oh_sun_open': None, 'oh_sun_close': None,
    },
    'sites': [
        {'id': 't11-cl', 'name': 'Maple Dental', 'active': True,
         'address_line_1': '22 Queen Square', 'town': 'Bristol', 'postcode': 'BS1 4NH',
         'phone_number': '0117 123 1001', 'email': 'clinic@valleydental.co.uk',
         'monday_open': '09:00', 'monday_close': '17:30',
         'tuesday_open': '09:00', 'tuesday_close': '17:30',
         'wednesday_open': '09:00', 'wednesday_close': '17:30',
         'thursday_open': '09:00', 'thursday_close': '17:30',
         'friday_open': '09:00', 'friday_close': '17:30',
         'saturday_open': None, 'saturday_close': None},
    ],
    'payment_plans': [
        _pp(1, 'NHS',             nhs=True,  dr=6,  hr=6, exam_dur=20, sp_dur=30, emg_dur=20),
        _pp(2, 'Private',                    dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
        _pp(3, 'Care Plan',  monthly='14.99', dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
        _pp(4, 'Premium Private', monthly='29.99', dr=12, hr=3, exam_dur=40, sp_dur=45, emg_dur=20),
    ],
    'contracts': [
        _contract(11, 't11-cl', 'VDX01', 2021, 2000, 26.00, loc_id='QUJ', contract_number='16C/VDX01/D'),
        _contract(11, 't11-cl', 'VDX01', 2022, 2050, 26.50, loc_id='QUJ', contract_number='16C/VDX01/D'),
        _contract(11, 't11-cl', 'VDX01', 2023, 2100, 27.00, loc_id='QUJ', contract_number='16C/VDX01/D'),
        _contract(11, 't11-cl', 'VDX01', 2024, 2100, 27.50, loc_id='QUJ', contract_number='16C/VDX01/D'),
        _contract(11, 't11-cl', 'VDX01', 2025, 2100, 28.00, loc_id='QUJ', contract_number='16C/VDX01/D'),
        _contract(11, 't11-cl', 'VDX01', 2026, 2100, 28.80, loc_id='QUJ', contract_number='16C/VDX01/D'),
    ],
    'acquisition_sources': [
        _acq('acq-11-01', 'Walk-in / Off the Street'), _acq('acq-11-02', 'Google Search'),
        _acq('acq-11-03', 'Word of Mouth'),            _acq('acq-11-04', 'NHS Referral'),
        _acq('acq-11-05', 'Patient Referral'),         _acq('acq-11-06', 'Website / Online'),
        _acq('acq-11-07', 'Social Media'),             _acq('acq-11-08', 'Local Advertisement'),
        _acq('acq-11-09', 'School / Employer Scheme'), _acq('acq-11-10', 'Returning Patient'),
    ],
    'cancellation_reasons': [
        _cr(1,  'Patient cancelled - short notice'),
        _cr(2,  'Patient cancelled - in advance'),
        _cr(3,  'Patient DNA (did not attend)'),
        _cr(4,  'Patient unwell'),
        _cr(5,  'Practice cancelled - practitioner unwell'),
        _cr(6,  'Practice cancelled - emergency'),
        _cr(7,  'Work completed at previous visit'),
        _cr(8,  'Treatment no longer required'),
        _cr(9,  'Patient request'),
        _cr(10, 'System error / admin'),
    ],
    'sundries': (
        [_sundry(11, 't11-cl', n, p) for n, p in [
            ('Electric Toothbrush (Oral-B)', 49.99), ('Replacement Brush Heads (4-pack)', 14.99),
            ('Whitening Toothpaste', 7.99), ('Interdental Brushes', 4.99),
            ('Fluoride Mouthwash (500ml)', 6.99), ('Home Whitening Kit', 149.00),
        ]]
    ),
    'waiting_lists': [
        _wl(11, 't11-cl', 'NHS New Patient', 60), _wl(11, 't11-cl', 'New Private Patient', 30),
    ],
    '_prac_defs': [
        {'id': 1, 'first_name': 'Nathan', 'last_name': 'Cole', 'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-cl', 'gdc_number': '1110001', 'nhs_pct': 0.22,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [1,3], 'late_end': '19:30', 'pp_ids': [1,2,4], 'performs_nhs': True, 'active': True},
        {'id': 2, 'first_name': 'Amara', 'last_name': 'Singh', 'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-cl', 'gdc_number': '1110002', 'nhs_pct': 0.15,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2,4], 'performs_nhs': True, 'active': True},
        {'id': 3, 'first_name': 'Patrick', 'last_name': 'Ryan', 'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-cl', 'gdc_number': '1110003', 'nhs_pct': 0.20,
         'work_days': [0,1,2,3], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': True, 'active': True},
        {'id': 4, 'first_name': 'Zoe', 'last_name': 'Crawford', 'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-cl', 'gdc_number': '1110004', 'nhs_pct': 0.18,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': True, 'active': True},
        {'id': 5, 'first_name': 'Kwame', 'last_name': 'Asante', 'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-cl', 'gdc_number': '1110005', 'nhs_pct': 0.20,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': True, 'active': True},
        {'id': 9, 'first_name': 'Claire', 'last_name': 'Hughes', 'title': 'Ms', 'role': 'hygienist',
         'site_id': 't11-cl', 'gdc_number': '1110009', 'nhs_pct': 0.15,
         'work_days': [0,2,4], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2,3], 'performs_nhs': True, 'active': True},
        {'id': 10, 'first_name': 'Rita', 'last_name': 'Osei', 'title': 'Ms', 'role': 'hygienist',
         'site_id': 't11-cl', 'gdc_number': '1110010', 'nhs_pct': 0.1,
         'work_days': [1,3,4], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2,3], 'performs_nhs': True, 'active': True},
        {'id': 11, 'first_name': 'Dev', 'last_name': 'Patel', 'title': 'Mr', 'role': 'hygienist',
         'site_id': 't11-cl', 'gdc_number': '1110011', 'nhs_pct': 0.12,
         'work_days': [0,1,3], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2,3], 'performs_nhs': True, 'active': True},
    ],
    '_site_patient_split': {'t11-cl': 1.0},
    '_params': {
        'active_rate':             0.95,
        'new_patient_rate':        0.223,
        # Measured on the live practice (tenant 100, patient appointments only, last 90
        # days): 1.93% DNA and 26.1% cancelled. _add_disruption emits these as EXTRA rows
        # against the visit that replaced them, so the cancel rate is solved backwards --
        # c/(1+c+d) = 0.26 gives c = 0.36, not 0.26.
        # 0.042, not 0.019, for the same backwards-solve -- and then a little higher again
        # because a DNA can only be recorded against a date that has passed, so the six
        # weeks either side of today draw from a thinner supply of source appointments
        # than the middle of the window does.
        'dna_rate':                0.042,
        'cancel_rate':             0.36,
        'treatment_followup_rate': 0.80,
        'max_tx_followups':        2,
        'bbyl_rate_tx':            0.78,
        'bbyl_rate_hyg':           0.78,
        'recall_booking_rate':     0.78,
        'plan_acceptance_rate':    0.65,
        'email_rate':              0.75,
        'phone_rate':              0.85,
    },
}

T12 = {
    'tenant_id': 12, 'nhs': False, 'has_ortho': False, 'price_mult': 1.25, 'n_patients': 7500,
    'domain': 'elaradental.co.uk',
    'practice': {
        'id': _u5('practice', 12), 'name': 'Elara Dental', 'nhs': False,
        'address_line_1': '14 George Street', 'address_line_2': None,
        'town': 'Edinburgh', 'postcode': 'EH2 2PF',
        'phone_number': '0131 100 0001', 'email_address': 'info@elaradental.co.uk',
        'patient_email_address': 'patients@elaradental.co.uk',
        'website': 'https://elaradental.co.uk', 'logo_url': None,
        'slug': 'elara-dental', 'time_zone': 'Europe/London',
        'medical_history_expiry_days': 365,
        'custom_patient_field_label_1': None, 'custom_patient_field_label_2': None,
        'oh_mon_open': '09:00', 'oh_mon_close': '17:30',
        'oh_tues_open': '09:00', 'oh_tues_close': '17:30',
        'oh_wed_open': '09:00', 'oh_wed_close': '17:30',
        'oh_thur_open': '09:00', 'oh_thur_close': '17:30',
        'oh_fri_open': '09:00', 'oh_fri_close': '17:30',
        'oh_sat_open': '09:00', 'oh_sat_close': '13:00',
        'oh_sun_open': None, 'oh_sun_close': None,
    },
    'sites': [
        {'id': 't12-gt', 'name': 'George Street', 'active': True,
         'address_line_1': '14 George Street', 'town': 'Edinburgh', 'postcode': 'EH2 2PF',
         'phone_number': '0131 100 1001', 'email': 'info@elaradental.co.uk',
         'monday_open': '09:00', 'monday_close': '17:30',
         'tuesday_open': '09:00', 'tuesday_close': '17:30',
         'wednesday_open': '09:00', 'wednesday_close': '17:30',
         'thursday_open': '09:00', 'thursday_close': '17:30',
         'friday_open': '09:00', 'friday_close': '17:30',
         'saturday_open': '09:00', 'saturday_close': '13:00'},
    ],
    'payment_plans': [
        _pp(1, 'Private',   dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
        _pp(2, 'Care Plan', monthly='17.99', dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
    ],
    'contracts': [],
    'acquisition_sources': [
        _acq('acq-12-01', 'Walk-in / Off the Street'), _acq('acq-12-02', 'Google Search'),
        _acq('acq-12-03', 'Patient Referral'),         _acq('acq-12-04', 'Website / Online'),
        _acq('acq-12-05', 'Social Media'),             _acq('acq-12-06', 'Specialist Referral'),
        _acq('acq-12-07', 'Instagram / Ads'),          _acq('acq-12-08', 'Local Dentist Referral'),
    ],
    'cancellation_reasons': [
        _cr(1, 'Patient cancelled - short notice'),
        _cr(2, 'Patient cancelled - in advance'),
        _cr(3, 'Patient DNA'),
        _cr(4, 'Practice cancelled - practitioner unwell'),
        _cr(5, 'Treatment no longer required'),
    ],
    'sundries': [_sundry(12, 't12-gt', n, p) for n, p in [
        ('Premium Electric Toothbrush', 89.99), ('Air Flosser', 49.99),
        ('Premium Home Whitening Kit', 199.00), ('Fluoride Mouthwash (500ml)', 8.99),
        ('Night Guard (stock)', 39.99), ('Whitening Toothpaste (premium)', 12.99),
    ]],
    'waiting_lists': [],
    '_prac_defs': [
        {'id': 1, 'first_name': 'Fiona',   'last_name': 'MacDonald', 'title': 'Dr', 'role': 'dentist',
         'site_id': 't12-gt', 'gdc_number': '1220001', 'nhs_pct': 0.0,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [1,3], 'late_end': '19:30', 'pp_ids': [1,2], 'performs_nhs': False, 'active': True},
        {'id': 2, 'first_name': 'Ross',    'last_name': 'Cameron',   'title': 'Dr', 'role': 'dentist',
         'site_id': 't12-gt', 'gdc_number': '1220002', 'nhs_pct': 0.0,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': False, 'active': True},
        {'id': 3, 'first_name': 'Preethi', 'last_name': 'Nair',      'title': 'Dr', 'role': 'dentist',
         'site_id': 't12-gt', 'gdc_number': '1220003', 'nhs_pct': 0.0,
         'work_days': [0,2,3,4,5], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': False, 'active': True},
        {'id': 4, 'first_name': 'Josh',    'last_name': 'Elliott',   'title': 'Dr', 'role': 'specialist',
         'site_id': 't12-gt', 'gdc_number': '1220004', 'nhs_pct': 0.0,
         'work_days': [0,1,2,3], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [1], 'performs_nhs': False, 'active': True},
        {'id': 5, 'first_name': 'Hannah',  'last_name': 'Wu',        'title': 'Dr', 'role': 'specialist',
         'site_id': 't12-gt', 'gdc_number': '1220005', 'nhs_pct': 0.0,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': False, 'active': True},
        {'id': 6, 'first_name': 'Kate',    'last_name': "O'Brien",   'title': 'Ms', 'role': 'hygienist',
         'site_id': 't12-gt', 'gdc_number': '1220006', 'nhs_pct': 0.0,
         'work_days': [0,1,3,4], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': False, 'active': True},
        {'id': 7, 'first_name': 'Anna',    'last_name': 'Johansson', 'title': 'Ms', 'role': 'hygienist',
         'site_id': 't12-gt', 'gdc_number': '1220007', 'nhs_pct': 0.0,
         'work_days': [1,2,4,5], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': False, 'active': True},
        {'id': 8, 'first_name': 'Mel',     'last_name': 'Peters',    'title': 'Ms', 'role': 'tco',
         'site_id': 't12-gt', 'gdc_number': None, 'nhs_pct': 0.0,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': False, 'active': True},
        {'id': 9, 'first_name': 'Simon',   'last_name': 'Brooks',    'title': 'Mr', 'role': 'tco',
         'site_id': 't12-gt', 'gdc_number': None, 'nhs_pct': 0.0,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': False, 'active': True},
    ],
    '_site_patient_split': {'t12-gt': 1.0},
}

SEED_TENANTS = {11: T11, 12: T12}
