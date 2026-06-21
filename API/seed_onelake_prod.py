"""
seed_onelake_prod.py  --  Seed Tenant 11 (Valley Dental Group) demo data into
                          the Production OneLake Lakehouse.

Usage:
    python API/seed_onelake_prod.py

Requirements (already installed):
    deltalake, pyarrow, pandas, azure-identity
"""
import sys, json, os
from datetime import datetime, timezone
import pandas as pd
import pyarrow as pa
from deltalake import write_deltalake
from azure.identity import InteractiveBrowserCredential

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_data import generate_tenant, _u5, _pp, _sundry, _wl, _acq, _cr, _contract

# ── OneLake config ────────────────────────────────────────────────────────────
WORKSPACE_GUID = "2490d322-e8cc-4e9e-a3dc-964ce6fe444f"
LAKEHOUSE_GUID = "868da63e-6570-461c-aa46-eade0ce99f91"
ONELAKE_HOST   = "onelake.dfs.fabric.microsoft.com"

def table_path(table_name: str) -> str:
    return (
        f"abfss://{WORKSPACE_GUID}@{ONELAKE_HOST}"
        f"/{LAKEHOUSE_GUID}/Tables/dbo/stage_{table_name}"
    )

# ── Auth ──────────────────────────────────────────────────────────────────────
_cred = None

def get_storage_options() -> dict:
    global _cred
    token = _cred.get_token("https://storage.azure.com/.default")
    return {"bearer_token": token.token}

# ── Write helper ──────────────────────────────────────────────────────────────
def write_stage(records: list, table_name: str):
    """Full overwrite of the entire table."""
    if not records:
        print(f"  {table_name}: 0 records (skipped)")
        return

    def _to_str(v):
        if v is None:                   return None
        if isinstance(v, bool):         return '1' if v else '0'
        if isinstance(v, (dict, list)): return json.dumps(v)
        return str(v)

    rows = [{k: _to_str(v) for k, v in r.items()} for r in records]
    df   = pd.DataFrame(rows).astype("string")
    tbl  = pa.Table.from_pandas(df, preserve_index=False)

    print(f"  {table_name}: writing {len(records):,} rows...", end="", flush=True)
    write_deltalake(
        table_path(table_name),
        tbl,
        mode            = "overwrite",
        schema_mode     = "merge",
        storage_options = get_storage_options(),
    )
    print(" done.")


# ── Tenant 11: Valley Dental Group ───────────────────────────────────────────

T11 = {
    'tenant_id': 11, 'nhs': True, 'has_ortho': True, 'price_mult': 1.0, 'n_patients': 15000,
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
        {'id': 't11-cl', 'name': 'Clifton', 'active': True,
         'address_line_1': '22 Queen Square', 'town': 'Bristol', 'postcode': 'BS1 4NH',
         'phone_number': '0117 123 1001', 'email': 'clifton@valleydental.co.uk',
         'monday_open': '09:00', 'monday_close': '17:30',
         'tuesday_open': '09:00', 'tuesday_close': '17:30',
         'wednesday_open': '09:00', 'wednesday_close': '17:30',
         'thursday_open': '09:00', 'thursday_close': '17:30',
         'friday_open': '09:00', 'friday_close': '17:30',
         'saturday_open': None, 'saturday_close': None},
        {'id': 't11-hb', 'name': 'Harbourside', 'active': True,
         'address_line_1': '8 Harbourside Walk', 'town': 'Bristol', 'postcode': 'BS1 5TR',
         'phone_number': '0117 123 2001', 'email': 'harbourside@valleydental.co.uk',
         'monday_open': '09:00', 'monday_close': '17:30',
         'tuesday_open': '09:00', 'tuesday_close': '17:30',
         'wednesday_open': '09:00', 'wednesday_close': '17:30',
         'thursday_open': '09:00', 'thursday_close': '17:30',
         'friday_open': '09:00', 'friday_close': '17:30',
         'saturday_open': None, 'saturday_close': None},
        {'id': 't11-bm', 'name': 'Bedminster', 'active': True,
         'address_line_1': '55 North Street', 'town': 'Bristol', 'postcode': 'BS3 1EN',
         'phone_number': '0117 123 3001', 'email': 'bedminster@valleydental.co.uk',
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
        _contract(11, 't11-cl', 'VDX01', 2023, 1350, 26.50, loc_id='QUJ', contract_number='16C/VDX01/D'),
        _contract(11, 't11-cl', 'VDX01', 2024, 1400, 27.50, loc_id='QUJ', contract_number='16C/VDX01/D'),
        _contract(11, 't11-cl', 'VDX01', 2025, 1440, 28.00, loc_id='QUJ', contract_number='16C/VDX01/D'),
        _contract(11, 't11-cl', 'VDX01', 2026, 1460, 28.80, loc_id='QUJ', contract_number='16C/VDX01/D'),
        _contract(11, 't11-cl', 'VDX01', 2023, 0, 0, uoa_target=260, uoa_val=80.00, loc_id='QUJ', contract_number='16C/VDX01/O', is_ortho=True),
        _contract(11, 't11-cl', 'VDX01', 2024, 0, 0, uoa_target=280, uoa_val=82.00, loc_id='QUJ', contract_number='16C/VDX01/O', is_ortho=True),
        _contract(11, 't11-cl', 'VDX01', 2025, 0, 0, uoa_target=295, uoa_val=84.00, loc_id='QUJ', contract_number='16C/VDX01/O', is_ortho=True),
        _contract(11, 't11-cl', 'VDX01', 2026, 0, 0, uoa_target=295, uoa_val=86.00, loc_id='QUJ', contract_number='16C/VDX01/O', is_ortho=True),
        _contract(11, 't11-hb', 'VDX02', 2023, 1750, 26.00, loc_id='QUJ', contract_number='16C/VDX02/D'),
        _contract(11, 't11-hb', 'VDX02', 2024, 1700, 27.00, loc_id='QUJ', contract_number='16C/VDX02/D'),
        _contract(11, 't11-hb', 'VDX02', 2025, 1680, 27.80, loc_id='QUJ', contract_number='16C/VDX02/D'),
        _contract(11, 't11-hb', 'VDX02', 2026, 1675, 28.50, loc_id='QUJ', contract_number='16C/VDX02/D'),
        _contract(11, 't11-bm', 'VDX03', 2023, 2750, 26.50, loc_id='QUJ', contract_number='16C/VDX03/D'),
        _contract(11, 't11-bm', 'VDX03', 2024, 2700, 27.50, loc_id='QUJ', contract_number='16C/VDX03/D'),
        _contract(11, 't11-bm', 'VDX03', 2025, 2640, 28.00, loc_id='QUJ', contract_number='16C/VDX03/D'),
        _contract(11, 't11-bm', 'VDX03', 2026, 2600, 28.80, loc_id='QUJ', contract_number='16C/VDX03/D'),
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
        ]] +
        [_sundry(11, 't11-hb', n, p) for n, p in [
            ('Electric Toothbrush (Oral-B)', 49.99), ('Interdental Brushes', 4.99),
            ('Fluoride Mouthwash (500ml)', 6.99), ('Home Whitening Kit', 149.00),
        ]] +
        [_sundry(11, 't11-bm', n, p) for n, p in [
            ('Electric Toothbrush (Oral-B)', 49.99), ('Interdental Brushes', 4.99),
            ('Fluoride Mouthwash (500ml)', 6.99),
        ]]
    ),
    'waiting_lists': [
        _wl(11, 't11-cl', 'NHS New Patient', 60), _wl(11, 't11-cl', 'New Private Patient', 30),
        _wl(11, 't11-hb', 'NHS New Patient', 45),
        _wl(11, 't11-bm', 'NHS New Patient', 30), _wl(11, 't11-bm', 'New Private Patient', 14),
    ],
    '_prac_defs': [
        {'id': 1,  'first_name': 'Nathan',  'last_name': 'Cole',     'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-cl', 'gdc_number': '1110001', 'nhs_pct': 0.20,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [1,3], 'late_end': '19:30', 'pp_ids': [1,2,4], 'performs_nhs': True, 'active': True},
        {'id': 2,  'first_name': 'Amara',   'last_name': 'Singh',    'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-cl', 'gdc_number': '1110002', 'nhs_pct': 0.0,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [2,4], 'performs_nhs': False, 'active': True},
        {'id': 3,  'first_name': 'Patrick', 'last_name': 'Ryan',     'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-hb', 'gdc_number': '1110003', 'nhs_pct': 0.05,
         'work_days': [0,1,2,3], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': True, 'active': True},
        {'id': 4,  'first_name': 'Zoe',     'last_name': 'Crawford', 'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-bm', 'gdc_number': '1110004', 'nhs_pct': 0.18,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': True, 'active': True},
        {'id': 5,  'first_name': 'Kwame',   'last_name': 'Asante',   'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-bm', 'gdc_number': '1110005', 'nhs_pct': 0.15,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2], 'performs_nhs': True, 'active': True},
        {'id': 6,  'first_name': 'Layla',   'last_name': 'Morris',   'title': 'Dr', 'role': 'dentist',
         'site_id': 't11-cl', 'gdc_number': '1110006', 'nhs_pct': 0.20,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2,4], 'performs_nhs': True, 'active': True},
        {'id': 7,  'first_name': 'Tomas',   'last_name': 'Kowalski', 'title': 'Dr', 'role': 'orthodontist',
         'site_id': 't11-cl', 'gdc_number': '1110007', 'nhs_pct': 0.0,
         'work_days': [0,1,2,3], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [2], 'performs_nhs': False, 'active': True},
        {'id': 8,  'first_name': 'Isabel',  'last_name': 'Grant',    'title': 'Dr', 'role': 'orthodontist',
         'site_id': 't11-cl', 'gdc_number': '1110008', 'nhs_pct': 0.0,
         'work_days': [0,1,2,3], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [2], 'performs_nhs': False, 'active': True,
         'has_uoa_contract': True},
        {'id': 9,  'first_name': 'Claire',  'last_name': 'Hughes',   'title': 'Ms', 'role': 'hygienist',
         'site_id': 't11-cl', 'gdc_number': '1110009', 'nhs_pct': 0.15,
         'work_days': [0,2,4], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2,3], 'performs_nhs': True, 'active': True},
        {'id': 10, 'first_name': 'Rita',    'last_name': 'Osei',     'title': 'Ms', 'role': 'hygienist',
         'site_id': 't11-hb', 'gdc_number': '1110010', 'nhs_pct': 0.10,
         'work_days': [1,3,4], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2,3], 'performs_nhs': True, 'active': True},
        {'id': 11, 'first_name': 'Dev',     'last_name': 'Patel',    'title': 'Mr', 'role': 'hygienist',
         'site_id': 't11-bm', 'gdc_number': '1110011', 'nhs_pct': 0.12,
         'work_days': [0,1,3], 'start_time': '09:00', 'end_time': '17:00',
         'late_days': [], 'late_end': None, 'pp_ids': [1,2,3], 'performs_nhs': True, 'active': True},
        {'id': 12, 'first_name': 'Emma',    'last_name': 'Ford',     'title': 'Ms', 'role': 'tco',
         'site_id': 't11-cl', 'gdc_number': None, 'nhs_pct': 0.0,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [2,3,4], 'performs_nhs': False, 'active': True},
        {'id': 13, 'first_name': 'Ben',     'last_name': 'Walsh',    'title': 'Mr', 'role': 'tco',
         'site_id': 't11-bm', 'gdc_number': None, 'nhs_pct': 0.0,
         'work_days': [0,1,2,3,4], 'start_time': '09:00', 'end_time': '17:30',
         'late_days': [], 'late_end': None, 'pp_ids': [2,3], 'performs_nhs': False, 'active': True},
    ],
    '_site_patient_split': {'t11-cl': 0.45, 't11-hb': 0.30, 't11-bm': 0.25},
    '_params': {
        'active_rate':             0.95,
        'new_patient_rate':        0.223,
        'dna_rate':                0.028,
        'cancel_rate':             0.025,
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


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    print("Authenticating with Azure AD (browser window will open)...")
    global _cred
    _cred = InteractiveBrowserCredential()
    _cred.get_token("https://storage.azure.com/.default")
    print("Authenticated.\n")

    load_ts = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S')
    print(f"Load timestamp : {load_ts}")
    print(f"Target         : Production workspace (Valley Dental Group - Tenant 11)\n")

    TABLE_MAP = [
        ('practice',                   'practice',                   True),
        ('sites',                      'sites',                      False),
        ('users',                      'users',                      False),
        ('practitioners',              'practitioners',              False),
        ('payment_plans',              'payment_plans',              False),
        ('treatments',                 'treatments',                 False),
        ('treatment_categories',       'treatment_categories',       False),
        ('acquisition_sources',        'acquisition_sources',        False),
        ('cancellation_reasons',       'cancellation_reasons',       False),
        ('waiting_lists',              'waiting_lists',              False),
        ('sundries',                   'sundries',                   False),
        ('contracts',                  'contracts',                  False),
        ('fees',                       'fees',                       False),
        ('diary_breaks',               'practitioner_diary_breaks',  False),
        ('rooms',                      'rooms',                      False),
        ('patients',                   'patients',                   False),
        ('diary_entries',              'practitioner_diary_entries', False),
        ('appointments',               'appointments',               False),
        ('invoices',                   'invoices',                   False),
        ('invoice_items',              'invoice_items',              False),
        ('payments',                   'payments',                   False),
        ('treatment_plans',            'treatment_plans',            False),
        ('treatment_plan_items',       'treatment_plan_items',       False),
        ('recalls',                    'recalls',                    False),
        ('nhs_claims',                 'nhs_claims',                 False),
        ('patient_stats',              'patient_stats',              False),
        ('payment_allocations',        'payment_allocations',        False),
        ('payment_explanations',       'payment_explanations',       False),
        ('treatment_appts',            'treatment_appointments',     False),
        ('patient_referrals',          'patient_referrals',         False),
        ('accounts',                   'accounts',                  False),
    ]

    print(f'Generating Tenant 11: Valley Dental Group (15,000 patients)...', flush=True)
    data = generate_tenant(T11)
    print(f"  patients={len(data['patients']):,}  "
          f"apts={len(data['appointments']):,}  "
          f"plans={len(data['treatment_plans']):,}  "
          f"invoices={len(data['invoices']):,}  "
          f"claims={len(data['nhs_claims']):,}")

    combined = {}
    for data_key, stage_name, wrap in TABLE_MAP:
        records = [data[data_key]] if wrap else data[data_key]
        for r in records:
            r['tenant_id']          = '11'
            r['DW_Stage_Loaded_At'] = load_ts
        combined[stage_name] = records

    print('\nWriting to OneLake (full overwrite per table)...')
    for _, stage_name, _ in TABLE_MAP:
        write_stage(combined[stage_name], stage_name)

    print('\nTenant 11 seeded. Run Audit.usp_Load_Bronze for tenant 11.')


if __name__ == '__main__':
    main()
