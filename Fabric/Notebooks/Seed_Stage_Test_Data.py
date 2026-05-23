# Fabric notebook source

# %% [markdown]
# # Seed_Stage_Test_Data
# Generates synthetic data for tenants 11-14 at full spec volumes and writes
# directly into LH_Dentally Lakehouse Delta tables (stage_* tables).
#
# Stage views are `SELECT * FROM LH_Dentally.dbo.stage_*` so the seeded rows
# automatically appear alongside API data (tenants 1-4) in all Bronze loads.
#
# **Prerequisites**
# 1. Attach LH_Dentally as the default lakehouse before running.
# 2. Upload `API/generate_data.py` to LH_Dentally > Files (root level).
#
# | Tenant | Practice | Location | Type | Patients |
# |--------|----------|----------|------|----------|
# | 11 | Valley Dental Group | Bristol | NHS + ortho, 3 sites | 3,700 |
# | 12 | Elara Dental | Edinburgh | Private, 1 site | 7,500 |
# | 13 | NorthCity Dental | Leeds | NHS + private, 2 sites | 7,500 |
# | 14 | Eastside Dental | Nottingham | NHS + private, 1 site | 5,000 |

# %% [markdown]
# ## Cell 1 — Parameters
# Tag this cell as a Parameters cell (... menu -> Toggle parameter cell)

# %%
tenant_ids_to_seed = [11, 12, 13, 14]   # can narrow to single tenant for reruns
full_refresh       = True                # True = replace all rows for the tenant

# %% [markdown]
# ## Cell 2 — Imports and setup

# %%

import sys, json
from datetime import datetime, timezone

sys.path.insert(0, "/lakehouse/default/Files/")
from generate_data import (
    generate_tenant,
    _u5, _pp, _sundry, _wl, _acq, _cr, _contract,
)
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructType, StructField

load_timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
print(f"Load timestamp : {load_timestamp}")
print(f"Tenants to seed: {tenant_ids_to_seed}")

# %% [markdown]
# ## Cell 3 — write_stage helper

# %%
# All values stored as strings — Stage is raw landing, Bronze does the typing.
# Scoped to a single tenant_id so other tenants are never touched.
# -----------------------------------------------------------------------------

def write_stage(records, table_name, tenant_id):
    if not records:
        print(f"  {table_name}: 0 records (skipped)")
        return

    for r in records:
        r["tenant_id"]          = tenant_id
        r["DW_Stage_Loaded_At"] = load_timestamp

    all_keys = set()
    for r in records:
        all_keys.update(r.keys())
    schema = StructType([StructField(k, StringType(), True) for k in sorted(all_keys)])

    def _to_str(v):
        if v is None:
            return None
        elif isinstance(v, (dict, list)):
            return json.dumps(v)
        else:
            return str(v)

    str_records = [{k: _to_str(v) for k, v in r.items()} for r in records]
    df = spark.createDataFrame(str_records, schema=schema)
    full_table = f"stage_{table_name}"

    if spark.catalog.tableExists(full_table):
        df.write.format("delta").mode("overwrite") \
            .option("replaceWhere", f"tenant_id = '{tenant_id}'") \
            .option("mergeSchema", "true") \
            .saveAsTable(full_table)
    else:
        df.write.format("delta").mode("overwrite") \
            .option("overwriteSchema", "true") \
            .saveAsTable(full_table)

    print(f"  {table_name}: {len(records)} records -> {full_table}")

# %% [markdown]
# ## Cell 4 — T11: Valley Dental Group (Bristol, NHS + ortho, 3 sites, 15k patients)

# %%
# Mirrors T1 (Smile Group) structure at full spec volume.
# -----------------------------------------------------------------------------

T11 = {
    "tenant_id": 11, "nhs": True, "has_ortho": True, "price_mult": 1.0, "n_patients": 3700,
    "domain": "valleydental.co.uk",
    "practice": {
        "id": _u5("practice", 11), "name": "Valley Dental Group", "nhs": True,
        "address_line_1": "22 Queen Square", "address_line_2": None,
        "town": "Bristol", "postcode": "BS1 4NH",
        "phone_number": "0117 123 0001", "email_address": "info@valleydental.co.uk",
        "patient_email_address": "patients@valleydental.co.uk",
        "website": "https://valleydental.co.uk", "logo_url": None,
        "slug": "valley-dental", "time_zone": "Europe/London",
        "medical_history_expiry_days": 365,
        "custom_patient_field_label_1": None, "custom_patient_field_label_2": None,
        "oh_mon_open": "09:00", "oh_mon_close": "17:30",
        "oh_tues_open": "09:00", "oh_tues_close": "17:30",
        "oh_wed_open": "09:00", "oh_wed_close": "17:30",
        "oh_thur_open": "09:00", "oh_thur_close": "17:30",
        "oh_fri_open": "09:00", "oh_fri_close": "17:30",
        "oh_sat_open": None, "oh_sat_close": None,
        "oh_sun_open": None, "oh_sun_close": None,
    },
    "sites": [
        {"id": "t11-cl", "name": "Clifton", "active": True,
         "address_line_1": "22 Queen Square", "town": "Bristol", "postcode": "BS1 4NH",
         "phone": "0117 123 1001", "email": "clifton@valleydental.co.uk",
         "monday_open": "09:00", "monday_close": "17:30",
         "tuesday_open": "09:00", "tuesday_close": "17:30",
         "wednesday_open": "09:00", "wednesday_close": "17:30",
         "thursday_open": "09:00", "thursday_close": "17:30",
         "friday_open": "09:00", "friday_close": "17:30",
         "saturday_open": None, "saturday_close": None},
        {"id": "t11-hb", "name": "Harbourside", "active": True,
         "address_line_1": "8 Harbourside Walk", "town": "Bristol", "postcode": "BS1 5TR",
         "phone": "0117 123 2001", "email": "harbourside@valleydental.co.uk",
         "monday_open": "09:00", "monday_close": "17:30",
         "tuesday_open": "09:00", "tuesday_close": "17:30",
         "wednesday_open": "09:00", "wednesday_close": "17:30",
         "thursday_open": "09:00", "thursday_close": "17:30",
         "friday_open": "09:00", "friday_close": "17:30",
         "saturday_open": None, "saturday_close": None},
        {"id": "t11-bm", "name": "Bedminster", "active": True,
         "address_line_1": "55 North Street", "town": "Bristol", "postcode": "BS3 1EN",
         "phone": "0117 123 3001", "email": "bedminster@valleydental.co.uk",
         "monday_open": "09:00", "monday_close": "17:30",
         "tuesday_open": "09:00", "tuesday_close": "17:30",
         "wednesday_open": "09:00", "wednesday_close": "17:30",
         "thursday_open": "09:00", "thursday_close": "17:30",
         "friday_open": "09:00", "friday_close": "17:30",
         "saturday_open": None, "saturday_close": None},
    ],
    "payment_plans": [
        _pp(1, "NHS",            nhs=True,  dr=6,  hr=6, exam_dur=20, sp_dur=30, emg_dur=20),
        _pp(2, "Private",                   dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
        _pp(3, "Care Plan",  monthly="14.99", dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
        _pp(4, "Premium Private", monthly="29.99", dr=12, hr=3, exam_dur=40, sp_dur=45, emg_dur=20),
    ],
    "contracts": [
        _contract(11, "t11-cl", "VDX01", 2023, 1350, 26.50, loc_id="QUJ", contract_number="16C/VDX01/D"),
        _contract(11, "t11-cl", "VDX01", 2024, 1400, 27.50, loc_id="QUJ", contract_number="16C/VDX01/D"),
        _contract(11, "t11-cl", "VDX01", 2025, 1440, 28.00, loc_id="QUJ", contract_number="16C/VDX01/D"),
        _contract(11, "t11-cl", "VDX01", 2026, 1460, 28.80, loc_id="QUJ", contract_number="16C/VDX01/D"),
        _contract(11, "t11-cl", "VDX01", 2023, 0, 0, uoa_target=260, uoa_val=80.00, loc_id="QUJ", contract_number="16C/VDX01/O", is_ortho=True),
        _contract(11, "t11-cl", "VDX01", 2024, 0, 0, uoa_target=280, uoa_val=82.00, loc_id="QUJ", contract_number="16C/VDX01/O", is_ortho=True),
        _contract(11, "t11-cl", "VDX01", 2025, 0, 0, uoa_target=295, uoa_val=84.00, loc_id="QUJ", contract_number="16C/VDX01/O", is_ortho=True),
        _contract(11, "t11-cl", "VDX01", 2026, 0, 0, uoa_target=295, uoa_val=86.00, loc_id="QUJ", contract_number="16C/VDX01/O", is_ortho=True),
        _contract(11, "t11-hb", "VDX02", 2023, 1750, 26.00, loc_id="QUJ", contract_number="16C/VDX02/D"),
        _contract(11, "t11-hb", "VDX02", 2024, 1700, 27.00, loc_id="QUJ", contract_number="16C/VDX02/D"),
        _contract(11, "t11-hb", "VDX02", 2025, 1680, 27.80, loc_id="QUJ", contract_number="16C/VDX02/D"),
        _contract(11, "t11-hb", "VDX02", 2026, 1675, 28.50, loc_id="QUJ", contract_number="16C/VDX02/D"),
        _contract(11, "t11-bm", "VDX03", 2023, 2750, 26.50, loc_id="QUJ", contract_number="16C/VDX03/D"),
        _contract(11, "t11-bm", "VDX03", 2024, 2700, 27.50, loc_id="QUJ", contract_number="16C/VDX03/D"),
        _contract(11, "t11-bm", "VDX03", 2025, 2640, 28.00, loc_id="QUJ", contract_number="16C/VDX03/D"),
        _contract(11, "t11-bm", "VDX03", 2026, 2600, 28.80, loc_id="QUJ", contract_number="16C/VDX03/D"),
    ],
    "acquisition_sources": [
        _acq("acq-11-01", "Walk-in / Off the Street"), _acq("acq-11-02", "Google Search"),
        _acq("acq-11-03", "Word of Mouth"),            _acq("acq-11-04", "NHS Referral"),
        _acq("acq-11-05", "Patient Referral"),         _acq("acq-11-06", "Website / Online"),
        _acq("acq-11-07", "Social Media"),             _acq("acq-11-08", "Local Advertisement"),
        _acq("acq-11-09", "School / Employer Scheme"), _acq("acq-11-10", "Returning Patient"),
    ],
    "cancellation_reasons": [
        _cr("cr-11-01", "Patient cancelled - short notice"),
        _cr("cr-11-02", "Patient cancelled - in advance"),
        _cr("cr-11-03", "Patient DNA (did not attend)"),
        _cr("cr-11-04", "Patient unwell"),
        _cr("cr-11-05", "Practice cancelled - practitioner unwell"),
        _cr("cr-11-06", "Practice cancelled - emergency"),
        _cr("cr-11-07", "Work completed at previous visit"),
        _cr("cr-11-08", "Treatment no longer required"),
        _cr("cr-11-09", "Patient request"),
        _cr("cr-11-10", "System error / admin"),
    ],
    "sundries": (
        [_sundry(11, "t11-cl", n, p) for n, p in [
            ("Electric Toothbrush (Oral-B)", 49.99), ("Replacement Brush Heads (4-pack)", 14.99),
            ("Whitening Toothpaste", 7.99), ("Interdental Brushes", 4.99),
            ("Fluoride Mouthwash (500ml)", 6.99), ("Home Whitening Kit", 149.00),
        ]] +
        [_sundry(11, "t11-hb", n, p) for n, p in [
            ("Electric Toothbrush (Oral-B)", 49.99), ("Interdental Brushes", 4.99),
            ("Fluoride Mouthwash (500ml)", 6.99), ("Home Whitening Kit", 149.00),
        ]] +
        [_sundry(11, "t11-bm", n, p) for n, p in [
            ("Electric Toothbrush (Oral-B)", 49.99), ("Interdental Brushes", 4.99),
            ("Fluoride Mouthwash (500ml)", 6.99),
        ]]
    ),
    "waiting_lists": [
        _wl(11, "t11-cl", "NHS New Patient",      60), _wl(11, "t11-cl", "New Private Patient", 30),
        _wl(11, "t11-hb", "NHS New Patient",      45),
        _wl(11, "t11-bm", "NHS New Patient",      30), _wl(11, "t11-bm", "New Private Patient", 14),
    ],
    "_prac_defs": [
        {"id": 1,  "first_name": "Nathan",   "last_name": "Cole",      "title": "Dr", "role": "dentist",
         "site_id": "t11-cl", "gdc_number": "1110001", "nhs_pct": 0.20,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [1,3], "late_end": "19:30", "pp_ids": [1,2,4], "performs_nhs": True, "active": True},
        {"id": 2,  "first_name": "Amara",    "last_name": "Singh",     "title": "Dr", "role": "dentist",
         "site_id": "t11-cl", "gdc_number": "1110002", "nhs_pct": 0.0,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [2,4], "performs_nhs": False, "active": True},
        {"id": 3,  "first_name": "Patrick",  "last_name": "Ryan",      "title": "Dr", "role": "dentist",
         "site_id": "t11-hb", "gdc_number": "1110003", "nhs_pct": 0.05,
         "work_days": [0,1,2,3], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2], "performs_nhs": True, "active": True},
        {"id": 4,  "first_name": "Zoe",      "last_name": "Crawford",  "title": "Dr", "role": "dentist",
         "site_id": "t11-bm", "gdc_number": "1110004", "nhs_pct": 0.18,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2], "performs_nhs": True, "active": True},
        {"id": 5,  "first_name": "Kwame",    "last_name": "Asante",    "title": "Dr", "role": "dentist",
         "site_id": "t11-bm", "gdc_number": "1110005", "nhs_pct": 0.15,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2], "performs_nhs": True, "active": True},
        {"id": 6,  "first_name": "Layla",    "last_name": "Morris",    "title": "Dr", "role": "dentist",
         "site_id": "t11-cl", "gdc_number": "1110006", "nhs_pct": 0.20,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2,4], "performs_nhs": True, "active": True},
        {"id": 7,  "first_name": "Tomas",    "last_name": "Kowalski",  "title": "Dr", "role": "orthodontist",
         "site_id": "t11-cl", "gdc_number": "1110007", "nhs_pct": 0.0,
         "work_days": [0,1,2,3], "start_time": "09:00", "end_time": "17:00",
         "late_days": [], "late_end": None, "pp_ids": [2], "performs_nhs": False, "active": True},
        {"id": 8,  "first_name": "Isabel",   "last_name": "Grant",     "title": "Dr", "role": "orthodontist",
         "site_id": "t11-cl", "gdc_number": "1110008", "nhs_pct": 0.0,
         "work_days": [0,1,2,3], "start_time": "09:00", "end_time": "17:00",
         "late_days": [], "late_end": None, "pp_ids": [2], "performs_nhs": False, "active": True,
         "has_uoa_contract": True},
        {"id": 9,  "first_name": "Claire",   "last_name": "Hughes",    "title": "Ms", "role": "hygienist",
         "site_id": "t11-cl", "gdc_number": "1110009", "nhs_pct": 0.15,
         "work_days": [0,2,4], "start_time": "09:00", "end_time": "17:00",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 10, "first_name": "Rita",     "last_name": "Osei",      "title": "Ms", "role": "hygienist",
         "site_id": "t11-hb", "gdc_number": "1110010", "nhs_pct": 0.10,
         "work_days": [1,3,4], "start_time": "09:00", "end_time": "17:00",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 11, "first_name": "Dev",      "last_name": "Patel",     "title": "Mr", "role": "hygienist",
         "site_id": "t11-bm", "gdc_number": "1110011", "nhs_pct": 0.12,
         "work_days": [0,1,3], "start_time": "09:00", "end_time": "17:00",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 12, "first_name": "Emma",     "last_name": "Ford",      "title": "Ms", "role": "tco",
         "site_id": "t11-cl", "gdc_number": None, "nhs_pct": 0.0,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [2,3,4], "performs_nhs": False, "active": True},
        {"id": 13, "first_name": "Ben",      "last_name": "Walsh",     "title": "Mr", "role": "tco",
         "site_id": "t11-bm", "gdc_number": None, "nhs_pct": 0.0,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [2,3], "performs_nhs": False, "active": True},
    ],
    "_site_patient_split": {"t11-cl": 0.45, "t11-hb": 0.30, "t11-bm": 0.25},
    "_params": {
        # Scale: 3700 patients × 0.95 active ≈ 3,515 ≈ target 3,500
        "active_rate": 0.95,
        # New patients: 3700 × 0.223 ≈ 825 join during 3yr window → ~275/year
        "new_patient_rate": 0.223,
        # DNA rate: target 3%; ~2.8% gives headroom within 20% band
        "dna_rate": 0.028,
        "cancel_rate": 0.025,
        # Treatment mix: 2 attempts per exam at 80% → exam ratio ~30% (target 28%)
        "treatment_followup_rate": 0.80,
        "max_tx_followups": 2,
        # BBYL: target 72%; high rates in data ready for when pipeline col is confirmed
        "bbyl_rate_tx": 0.78,
        "bbyl_rate_hyg": 0.78,
        "recall_booking_rate": 0.78,
        # Acceptance rate: target 65%
        "plan_acceptance_rate": 0.65,
    },
}

# %% [markdown]
# ## Cell 5 — T12: Elara Dental (Edinburgh, private-only, 1 site, 7.5k patients)

# %%
# Mirrors T2 (Bright Dental) structure at full spec volume.
# -----------------------------------------------------------------------------

T12 = {
    "tenant_id": 12, "nhs": False, "has_ortho": False, "price_mult": 1.25, "n_patients": 7500,
    "domain": "elaradental.co.uk",
    "practice": {
        "id": _u5("practice", 12), "name": "Elara Dental", "nhs": False,
        "address_line_1": "14 George Street", "address_line_2": None,
        "town": "Edinburgh", "postcode": "EH2 2PF",
        "phone_number": "0131 100 0001", "email_address": "info@elaradental.co.uk",
        "patient_email_address": "patients@elaradental.co.uk",
        "website": "https://elaradental.co.uk", "logo_url": None,
        "slug": "elara-dental", "time_zone": "Europe/London",
        "medical_history_expiry_days": 365,
        "custom_patient_field_label_1": None, "custom_patient_field_label_2": None,
        "oh_mon_open": "09:00", "oh_mon_close": "17:30",
        "oh_tues_open": "09:00", "oh_tues_close": "17:30",
        "oh_wed_open": "09:00", "oh_wed_close": "17:30",
        "oh_thur_open": "09:00", "oh_thur_close": "17:30",
        "oh_fri_open": "09:00", "oh_fri_close": "17:30",
        "oh_sat_open": "09:00", "oh_sat_close": "13:00",
        "oh_sun_open": None, "oh_sun_close": None,
    },
    "sites": [
        {"id": "t12-gt", "name": "George Street", "active": True,
         "address_line_1": "14 George Street", "town": "Edinburgh", "postcode": "EH2 2PF",
         "phone": "0131 100 1001", "email": "info@elaradental.co.uk",
         "monday_open": "09:00", "monday_close": "17:30",
         "tuesday_open": "09:00", "tuesday_close": "17:30",
         "wednesday_open": "09:00", "wednesday_close": "17:30",
         "thursday_open": "09:00", "thursday_close": "17:30",
         "friday_open": "09:00", "friday_close": "17:30",
         "saturday_open": "09:00", "saturday_close": "13:00"},
    ],
    "payment_plans": [
        _pp(1, "Private",   dr=12, hr=6,  exam_dur=30, sp_dur=45, emg_dur=20),
        _pp(2, "Care Plan", monthly="17.99", dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
    ],
    "contracts": [],
    "acquisition_sources": [
        _acq("acq-12-01", "Walk-in / Off the Street"), _acq("acq-12-02", "Google Search"),
        _acq("acq-12-03", "Patient Referral"),         _acq("acq-12-04", "Website / Online"),
        _acq("acq-12-05", "Social Media"),             _acq("acq-12-06", "Specialist Referral"),
        _acq("acq-12-07", "Instagram / Ads"),          _acq("acq-12-08", "Local Dentist Referral"),
    ],
    "cancellation_reasons": [
        _cr("cr-12-01", "Patient cancelled - short notice"),
        _cr("cr-12-02", "Patient cancelled - in advance"),
        _cr("cr-12-03", "Patient DNA"),
        _cr("cr-12-04", "Practice cancelled - practitioner unwell"),
        _cr("cr-12-05", "Treatment no longer required"),
    ],
    "sundries": [_sundry(12, "t12-gt", n, p) for n, p in [
        ("Premium Electric Toothbrush", 89.99), ("Air Flosser", 49.99),
        ("Premium Home Whitening Kit", 199.00), ("Fluoride Mouthwash (500ml)", 8.99),
        ("Night Guard (stock)", 39.99), ("Whitening Toothpaste (premium)", 12.99),
    ]],
    "waiting_lists": [],
    "_prac_defs": [
        {"id": 1, "first_name": "Fiona",     "last_name": "MacDonald",  "title": "Dr", "role": "dentist",
         "site_id": "t12-gt", "gdc_number": "1220001", "nhs_pct": 0.0,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [1,3], "late_end": "19:30", "pp_ids": [1,2], "performs_nhs": False, "active": True},
        {"id": 2, "first_name": "Ross",      "last_name": "Cameron",    "title": "Dr", "role": "dentist",
         "site_id": "t12-gt", "gdc_number": "1220002", "nhs_pct": 0.0,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2], "performs_nhs": False, "active": True},
        {"id": 3, "first_name": "Preethi",   "last_name": "Nair",       "title": "Dr", "role": "dentist",
         "site_id": "t12-gt", "gdc_number": "1220003", "nhs_pct": 0.0,
         "work_days": [0,2,3,4,5], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2], "performs_nhs": False, "active": True},
        {"id": 4, "first_name": "Josh",      "last_name": "Elliott",    "title": "Dr", "role": "specialist",
         "site_id": "t12-gt", "gdc_number": "1220004", "nhs_pct": 0.0,
         "work_days": [0,1,2,3], "start_time": "09:00", "end_time": "17:00",
         "late_days": [], "late_end": None, "pp_ids": [1], "performs_nhs": False, "active": True},
        {"id": 5, "first_name": "Hannah",    "last_name": "Wu",         "title": "Dr", "role": "specialist",
         "site_id": "t12-gt", "gdc_number": "1220005", "nhs_pct": 0.0,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2], "performs_nhs": False, "active": True},
        {"id": 6, "first_name": "Kate",      "last_name": "O'Brien",    "title": "Ms", "role": "hygienist",
         "site_id": "t12-gt", "gdc_number": "1220006", "nhs_pct": 0.0,
         "work_days": [0,1,3,4], "start_time": "09:00", "end_time": "17:00",
         "late_days": [], "late_end": None, "pp_ids": [1,2], "performs_nhs": False, "active": True},
        {"id": 7, "first_name": "Anna",      "last_name": "Johansson",  "title": "Ms", "role": "hygienist",
         "site_id": "t12-gt", "gdc_number": "1220007", "nhs_pct": 0.0,
         "work_days": [1,2,4,5], "start_time": "09:00", "end_time": "17:00",
         "late_days": [], "late_end": None, "pp_ids": [1,2], "performs_nhs": False, "active": True},
        {"id": 8, "first_name": "Mel",       "last_name": "Peters",     "title": "Ms", "role": "tco",
         "site_id": "t12-gt", "gdc_number": None, "nhs_pct": 0.0,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2], "performs_nhs": False, "active": True},
        {"id": 9, "first_name": "Simon",     "last_name": "Brooks",     "title": "Mr", "role": "tco",
         "site_id": "t12-gt", "gdc_number": None, "nhs_pct": 0.0,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2], "performs_nhs": False, "active": True},
    ],
    "_site_patient_split": {"t12-gt": 1.0},
}

# %% [markdown]
# ## Cell 6 — T13: NorthCity Dental (Leeds, NHS + private, 2 sites, 7.5k patients)

# %%
# Mirrors T3 (ClearSmile Manchester) structure at full spec volume.
# -----------------------------------------------------------------------------

T13 = {
    "tenant_id": 13, "nhs": True, "has_ortho": False, "price_mult": 0.90, "n_patients": 7500,
    "domain": "northcitydental.co.uk",
    "practice": {
        "id": _u5("practice", 13), "name": "NorthCity Dental", "nhs": True,
        "address_line_1": "6 Park Row", "address_line_2": None,
        "town": "Leeds", "postcode": "LS1 5HD",
        "phone_number": "0113 100 0001", "email_address": "info@northcitydental.co.uk",
        "patient_email_address": "patients@northcitydental.co.uk",
        "website": "https://northcitydental.co.uk", "logo_url": None,
        "slug": "northcity-dental", "time_zone": "Europe/London",
        "medical_history_expiry_days": 365,
        "custom_patient_field_label_1": None, "custom_patient_field_label_2": None,
        "oh_mon_open": "09:00", "oh_mon_close": "17:30",
        "oh_tues_open": "09:00", "oh_tues_close": "17:30",
        "oh_wed_open": "09:00", "oh_wed_close": "17:30",
        "oh_thur_open": "09:00", "oh_thur_close": "17:30",
        "oh_fri_open": "09:00", "oh_fri_close": "17:30",
        "oh_sat_open": "09:00", "oh_sat_close": "13:00",
        "oh_sun_open": None, "oh_sun_close": None,
    },
    "sites": [
        {"id": "t13-cc", "name": "City Centre", "active": True,
         "address_line_1": "6 Park Row", "town": "Leeds", "postcode": "LS1 5HD",
         "phone": "0113 100 1001", "email": "citycentre@northcitydental.co.uk",
         "monday_open": "09:00", "monday_close": "17:30",
         "tuesday_open": "09:00", "tuesday_close": "17:30",
         "wednesday_open": "09:00", "wednesday_close": "17:30",
         "thursday_open": "09:00", "thursday_close": "17:30",
         "friday_open": "09:00", "friday_close": "17:30",
         "saturday_open": None, "saturday_close": None},
        {"id": "t13-hd", "name": "Headingley", "active": True,
         "address_line_1": "20 Otley Road", "town": "Leeds", "postcode": "LS6 2AD",
         "phone": "0113 100 2001", "email": "headingley@northcitydental.co.uk",
         "monday_open": "09:00", "monday_close": "17:30",
         "tuesday_open": "09:00", "tuesday_close": "17:30",
         "wednesday_open": "09:00", "wednesday_close": "17:30",
         "thursday_open": "09:00", "thursday_close": "17:30",
         "friday_open": "09:00", "friday_close": "17:30",
         "saturday_open": "09:00", "saturday_close": "13:00"},
    ],
    "payment_plans": [
        _pp(1, "NHS",      nhs=True, dr=6,  hr=6, exam_dur=20, sp_dur=30, emg_dur=20),
        _pp(2, "Private",            dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
        _pp(3, "Care Plan", monthly="12.99", dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
    ],
    "contracts": [
        _contract(13, "t13-cc", "NCX01", 2023, 1200, 26.00, loc_id="QWY", contract_number="16C/NCX01/D"),
        _contract(13, "t13-cc", "NCX01", 2024, 1180, 27.00, loc_id="QWY", contract_number="16C/NCX01/D"),
        _contract(13, "t13-cc", "NCX01", 2025, 1150, 27.80, loc_id="QWY", contract_number="16C/NCX01/D"),
        _contract(13, "t13-cc", "NCX01", 2026, 1125, 28.50, loc_id="QWY", contract_number="16C/NCX01/D"),
        _contract(13, "t13-hd", "NCX02", 2023, 1250, 26.00, loc_id="QWY", contract_number="16C/NCX02/D"),
        _contract(13, "t13-hd", "NCX02", 2024, 1280, 27.00, loc_id="QWY", contract_number="16C/NCX02/D"),
        _contract(13, "t13-hd", "NCX02", 2025, 1320, 27.80, loc_id="QWY", contract_number="16C/NCX02/D"),
        _contract(13, "t13-hd", "NCX02", 2026, 1350, 28.50, loc_id="QWY", contract_number="16C/NCX02/D"),
    ],
    "acquisition_sources": [
        _acq("acq-13-01", "Walk-in / Off the Street"), _acq("acq-13-02", "Google Search"),
        _acq("acq-13-03", "Word of Mouth"),            _acq("acq-13-04", "NHS Referral"),
        _acq("acq-13-05", "Website / Online"),         _acq("acq-13-06", "Patient Referral"),
        _acq("acq-13-07", "Social Media"),
    ],
    "cancellation_reasons": [
        _cr("cr-13-01", "Patient cancelled - short notice"),
        _cr("cr-13-02", "Patient cancelled - in advance"),
        _cr("cr-13-03", "Patient DNA"),
        _cr("cr-13-04", "Patient unwell"),
        _cr("cr-13-05", "Practice cancelled - practitioner unwell"),
        _cr("cr-13-06", "Treatment no longer required"),
    ],
    "sundries": (
        [_sundry(13, "t13-cc", n, p) for n, p in [
            ("Electric Toothbrush", 44.99), ("Interdental Brushes", 4.99),
            ("Mouthwash (500ml)", 5.99),   ("Home Whitening Kit", 129.00),
        ]] +
        [_sundry(13, "t13-hd", n, p) for n, p in [
            ("Electric Toothbrush", 44.99), ("Interdental Brushes", 4.99),
            ("Mouthwash (500ml)", 5.99),   ("Home Whitening Kit", 129.00),
        ]]
    ),
    "waiting_lists": [
        _wl(13, "t13-cc", "NHS New Patient", 60),
        _wl(13, "t13-hd", "NHS New Patient", 30),
    ],
    "_prac_defs": [
        {"id": 1, "first_name": "Ravi",     "last_name": "Kumar",    "title": "Dr", "role": "dentist",
         "site_id": "t13-cc", "gdc_number": "1330001", "nhs_pct": 0.15,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 2, "first_name": "Lucy",     "last_name": "Hammond",  "title": "Dr", "role": "dentist",
         "site_id": "t13-hd", "gdc_number": "1330002", "nhs_pct": 0.25,
         "work_days": [0,1,2,3,4,5], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 3, "first_name": "Ali",      "last_name": "Hassan",   "title": "Dr", "role": "dentist",
         "site_id": "t13-cc", "gdc_number": "1330003", "nhs_pct": 0.20,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 4, "first_name": "Jasmine",  "last_name": "Patel",    "title": "Ms", "role": "hygienist",
         "site_id": "t13-cc", "gdc_number": "1330004", "nhs_pct": 0.15,
         "work_days": [0,2,4], "start_time": "09:00", "end_time": "17:00",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 5, "first_name": "Chris",    "last_name": "Green",    "title": "Mr", "role": "tco",
         "site_id": "t13-hd", "gdc_number": None, "nhs_pct": 0.0,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [2,3], "performs_nhs": False, "active": True},
    ],
    "_site_patient_split": {"t13-cc": 0.55, "t13-hd": 0.45},
}

# %% [markdown]
# ## Cell 7 — T14: Eastside Dental (Nottingham, NHS + private, 1 site, 5k patients)

# %%
# Mirrors T4 (ClearSmile Birmingham) structure at full spec volume.
# -----------------------------------------------------------------------------

T14 = {
    "tenant_id": 14, "nhs": True, "has_ortho": False, "price_mult": 0.90, "n_patients": 5000,
    "domain": "eastsidedental.co.uk",
    "practice": {
        "id": _u5("practice", 14), "name": "Eastside Dental", "nhs": True,
        "address_line_1": "10 Fletcher Gate", "address_line_2": None,
        "town": "Nottingham", "postcode": "NG1 2FZ",
        "phone_number": "0115 100 0001", "email_address": "info@eastsidedental.co.uk",
        "patient_email_address": "patients@eastsidedental.co.uk",
        "website": "https://eastsidedental.co.uk", "logo_url": None,
        "slug": "eastside-dental", "time_zone": "Europe/London",
        "medical_history_expiry_days": 365,
        "custom_patient_field_label_1": None, "custom_patient_field_label_2": None,
        "oh_mon_open": "09:00", "oh_mon_close": "17:30",
        "oh_tues_open": "09:00", "oh_tues_close": "17:30",
        "oh_wed_open": "09:00", "oh_wed_close": "17:30",
        "oh_thur_open": "09:00", "oh_thur_close": "17:30",
        "oh_fri_open": "09:00", "oh_fri_close": "17:30",
        "oh_sat_open": None, "oh_sat_close": None,
        "oh_sun_open": None, "oh_sun_close": None,
    },
    "sites": [
        {"id": "t14-fg", "name": "Fletcher Gate", "active": True,
         "address_line_1": "10 Fletcher Gate", "town": "Nottingham", "postcode": "NG1 2FZ",
         "phone": "0115 100 1001", "email": "info@eastsidedental.co.uk",
         "monday_open": "09:00", "monday_close": "17:30",
         "tuesday_open": "09:00", "tuesday_close": "17:30",
         "wednesday_open": "09:00", "wednesday_close": "17:30",
         "thursday_open": "09:00", "thursday_close": "17:30",
         "friday_open": "09:00", "friday_close": "17:30",
         "saturday_open": None, "saturday_close": None},
    ],
    "payment_plans": [
        _pp(1, "NHS",      nhs=True, dr=6,  hr=6, exam_dur=20, sp_dur=30, emg_dur=20),
        _pp(2, "Private",            dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
        _pp(3, "Care Plan", monthly="12.99", dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20),
    ],
    "contracts": [
        _contract(14, "t14-fg", "EDX01", 2023, 2100, 26.20, loc_id="QNO", contract_number="16C/EDX01/D"),
        _contract(14, "t14-fg", "EDX01", 2024, 2150, 27.20, loc_id="QNO", contract_number="16C/EDX01/D"),
        _contract(14, "t14-fg", "EDX01", 2025, 2200, 28.00, loc_id="QNO", contract_number="16C/EDX01/D"),
        _contract(14, "t14-fg", "EDX01", 2026, 2250, 28.80, loc_id="QNO", contract_number="16C/EDX01/D"),
    ],
    "acquisition_sources": [
        _acq("acq-14-01", "Walk-in / Off the Street"), _acq("acq-14-02", "Google Search"),
        _acq("acq-14-03", "Word of Mouth"),            _acq("acq-14-04", "NHS Referral"),
        _acq("acq-14-05", "Patient Referral"),         _acq("acq-14-06", "Website / Online"),
    ],
    "cancellation_reasons": [
        _cr("cr-14-01", "Patient cancelled - short notice"),
        _cr("cr-14-02", "Patient cancelled - in advance"),
        _cr("cr-14-03", "Patient DNA"),
        _cr("cr-14-04", "Patient unwell"),
        _cr("cr-14-05", "Practice cancelled - practitioner unwell"),
    ],
    "sundries": [_sundry(14, "t14-fg", n, p) for n, p in [
        ("Electric Toothbrush", 39.99), ("Interdental Brushes", 4.49),
        ("Mouthwash (500ml)", 5.49),   ("Fluoride Toothpaste", 5.99),
    ]],
    "waiting_lists": [_wl(14, "t14-fg", "NHS New Patient", 45)],
    "_prac_defs": [
        {"id": 1, "first_name": "Michael",  "last_name": "Byrne",   "title": "Dr", "role": "dentist",
         "site_id": "t14-fg", "gdc_number": "1440001", "nhs_pct": 0.22,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 2, "first_name": "Sunita",   "last_name": "Gupta",   "title": "Dr", "role": "dentist",
         "site_id": "t14-fg", "gdc_number": "1440002", "nhs_pct": 0.20,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 3, "first_name": "Aaron",    "last_name": "Lewis",   "title": "Dr", "role": "dentist",
         "site_id": "t14-fg", "gdc_number": "1440003", "nhs_pct": 0.18,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 4, "first_name": "Kim",      "last_name": "Bailey",  "title": "Ms", "role": "hygienist",
         "site_id": "t14-fg", "gdc_number": "1440004", "nhs_pct": 0.12,
         "work_days": [0,2,4], "start_time": "09:00", "end_time": "17:00",
         "late_days": [], "late_end": None, "pp_ids": [1,2,3], "performs_nhs": True, "active": True},
        {"id": 5, "first_name": "Tom",      "last_name": "Watts",   "title": "Mr", "role": "tco",
         "site_id": "t14-fg", "gdc_number": None, "nhs_pct": 0.0,
         "work_days": [0,1,2,3,4], "start_time": "09:00", "end_time": "17:30",
         "late_days": [], "late_end": None, "pp_ids": [2,3], "performs_nhs": False, "active": True},
    ],
    "_site_patient_split": {"t14-fg": 1.0},
}

SEED_TENANTS = {11: T11, 12: T12, 13: T13, 14: T14}

# %% [markdown]
# ## Cell 8 — Generate and write
# Generation time estimate: T11 ~20-30 min, T12-T14 ~5-15 min each.

# %%
# Each tenant is generated in full then written entity-by-entity.
# Generation time: T11 ~20-30 min, T12-T14 ~5-15 min each.
# -----------------------------------------------------------------------------

for tid in tenant_ids_to_seed:
    tdef = SEED_TENANTS[tid]
    print(f"\n{'='*60}")
    print(f"Tenant {tid}: {tdef['practice']['name']}  ({tdef['n_patients']:,} patients)")
    print(f"{'='*60}")

    print("  Generating data...")
    data = generate_tenant(tdef)
    print(f"  patients={len(data['patients']):,}  "
          f"apts={len(data['appointments']):,}  "
          f"plans={len(data['treatment_plans']):,}  "
          f"invoices={len(data['invoices']):,}  "
          f"claims={len(data['nhs_claims']):,}")

    print("  Writing reference data...")
    write_stage([data["practice"]],              "practice",                  tid)
    write_stage(data["sites"],                   "sites",                     tid)
    write_stage(data["users"],                   "users",                     tid)
    write_stage(data["practitioners"],           "practitioners",             tid)
    write_stage(data["payment_plans"],           "payment_plans",             tid)
    write_stage(data["treatments"],              "treatments",                tid)
    write_stage(data["treatment_categories"],    "treatment_categories",      tid)
    write_stage(data["acquisition_sources"],     "acquisition_sources",       tid)
    write_stage(data["cancellation_reasons"],    "cancellation_reasons",      tid)
    write_stage(data["waiting_lists"],           "waiting_lists",             tid)
    write_stage(data["sundries"],                "sundries",                  tid)
    write_stage(data["contracts"],               "contracts",                 tid)
    write_stage(data["fees"],                    "fees",                      tid)
    write_stage(data["diary_breaks"],            "practitioner_diary_breaks", tid)

    print("  Writing transactional data...")
    write_stage(data["patients"],                "patients",                  tid)
    write_stage(data["diary_entries"],           "practitioner_diary_entries",tid)
    write_stage(data["appointments"],            "appointments",              tid)
    write_stage(data["invoices"],                "invoices",                  tid)
    write_stage(data["invoice_items"],           "invoice_items",             tid)
    write_stage(data["payments"],                "payments",                  tid)
    write_stage(data["treatment_plans"],         "treatment_plans",           tid)
    write_stage(data["treatment_plan_items"],    "treatment_plan_items",      tid)
    write_stage(data["recalls"],                 "recalls",                   tid)
    write_stage(data["nhs_claims"],              "nhs_claims",                tid)
    write_stage(data["patient_stats"],           "patient_stats",             tid)
    write_stage(data["payment_allocations"],     "payment_allocations",       tid)
    write_stage(data["payment_explanations"],    "payment_explanations",      tid)
    write_stage(data["treatment_appts"],         "treatment_appointments",    tid)
    write_stage(data["patient_referrals"],       "patient_referrals",         tid)

    print(f"  Tenant {tid} complete.")

print("\nAll tenants seeded. Run Bronze.usp_Load_All for tenants 11-14.")
