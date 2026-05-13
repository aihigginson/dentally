"""
Dentally Mock API
-----------------
Mimics the real Dentally REST API with generated test data.
Matches real field names and JSON envelope structure.

Multi-tenant:
    Two practices are pre-loaded, each with its own API key.
    Tenant 1 — Smile Group (Oxford)    Bearer dev-mock-key-abc123
    Tenant 2 — Bright Dental (Brighton) Bearer dev-mock-key-tenant2
    Patient / appointment IDs overlap between tenants intentionally,
    to verify that Tenant_ID isolation in the ETL is working correctly.

Usage:
    python mock_api.py     ->  http://localhost:5000

Endpoints (all tenants):
    GET /v1/practice
    GET /v1/sites
    GET /v1/users
    GET /v1/practitioners              ?site_id=
    GET /v1/payment_plans
    GET /v1/treatments
    GET /v1/treatment_categories
    GET /v1/acquisition_sources
    GET /v1/sundries                   ?site_id=
    GET /v1/contracts                  ?site_id=
    GET /v1/fees                       ?payment_plan_id=  &treatment_id=
    GET /v1/patients                   ?site_id=  &active=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/patients/{id}
    GET /v1/accounts                   ?patient_id=  &page=  &per_page=
    GET /v1/patient_stats              ?patient_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/appointments               ?site_id=  &practitioner_id=  &patient_id=  &state=
                                       &after=YYYY-MM-DD  &before=YYYY-MM-DD  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/treatment_appointments     ?patient_id=  &treatment_plan_id=  &appointment_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/invoices                   ?site_id=  &patient_id=  &dated_after=  &dated_before=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/invoice_items              ?invoice_id=  &patient_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/payments                   ?site_id=  &patient_id=  &dated_after=  &dated_before=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/payment_explanations       ?payment_id=  &page=  &per_page=
    GET /v1/payment_allocations        ?patient_id=  &invoice_item_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/treatment_plans            ?site_id=  &patient_id=  &status=  &created_after=  &created_before=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/treatment_plan_items       ?treatment_plan_id=  &patient_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/recalls                    ?site_id=  &patient_id=  &practitioner_id=  &overdue=true  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/nhs_claims                 ?patient_id=  &contract_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/practitioner_diary_entries ?practitioner_id=  &site_id=  &date_after=  &date_before=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/practitioner_diary_breaks  ?practitioner_diary_id=  &page=  &per_page=
"""

import math
import os
import random
import uuid as _uuid_mod
from datetime import date, datetime, timedelta

from flask import Flask, g, jsonify, request

app = Flask(__name__)
random.seed(42)

TENANT1_KEY = os.environ.get('DENTALLY_API_KEY', 'dev-mock-key-abc123')
TENANT2_KEY = 'dev-mock-key-tenant2'
ALL_KEYS    = {TENANT1_KEY, TENANT2_KEY}


@app.before_request
def check_auth():
    if request.path == '/':
        return None
    key = request.headers.get('Authorization', '').removeprefix('Bearer ')
    if key not in ALL_KEYS:
        return jsonify({'error': 'Unauthorized'}), 401
    g.data = TENANT_DATA[key]


# ══════════════════════════════════════════════════════════════════════════════
# SHARED REFERENCE DATA  (identical for all tenants)
# ══════════════════════════════════════════════════════════════════════════════

TREATMENT_CATEGORIES = [
    {"id": 1, "name": "Examination & Preventive"},
    {"id": 2, "name": "Restorative"},
    {"id": 3, "name": "Endodontic"},
    {"id": 4, "name": "Surgical"},
    {"id": 5, "name": "Prosthetic"},
    {"id": 6, "name": "Cosmetic"},
    {"id": 7, "name": "Implant"},
    {"id": 8, "name": "Emergency"},
]

ACQUISITION_SOURCES = [
    {"id": "acq-001", "active": True,  "name": "Walk-in",      "notes": None},
    {"id": "acq-002", "active": True,  "name": "Referral",     "notes": "Patient referral"},
    {"id": "acq-003", "active": True,  "name": "Website",      "notes": None},
    {"id": "acq-004", "active": True,  "name": "Google",       "notes": None},
    {"id": "acq-005", "active": True,  "name": "Social Media", "notes": None},
    {"id": "acq-006", "active": False, "name": "Newspaper",    "notes": "Discontinued"},
]

TREATMENTS = [
    {"id": 1,  "name": "Examination",                   "code": "0101", "chart_type": "examination"},
    {"id": 2,  "name": "Scale and Polish",               "code": "0111", "chart_type": "hygiene"},
    {"id": 3,  "name": "X-Ray (bitewing)",               "code": "0201", "chart_type": "xray"},
    {"id": 4,  "name": "Filling (1 surface, composite)", "code": "0301", "chart_type": "restorative"},
    {"id": 5,  "name": "Filling (2 surface, composite)", "code": "0302", "chart_type": "restorative"},
    {"id": 6,  "name": "Filling (amalgam)",              "code": "0303", "chart_type": "restorative"},
    {"id": 7,  "name": "Extraction (simple)",            "code": "0401", "chart_type": "surgical"},
    {"id": 8,  "name": "Root Canal (anterior)",          "code": "0501", "chart_type": "endodontic"},
    {"id": 9,  "name": "Root Canal (molar)",             "code": "0502", "chart_type": "endodontic"},
    {"id": 10, "name": "Crown (porcelain fused metal)",  "code": "0601", "chart_type": "prosthetic"},
    {"id": 11, "name": "Crown (full porcelain)",         "code": "0602", "chart_type": "prosthetic"},
    {"id": 12, "name": "Denture (full upper)",           "code": "0701", "chart_type": "prosthetic"},
    {"id": 13, "name": "Whitening (home kit)",           "code": "0801", "chart_type": "cosmetic"},
    {"id": 14, "name": "Whitening (in-chair)",           "code": "0802", "chart_type": "cosmetic"},
    {"id": 15, "name": "Implant Consultation",           "code": "0901", "chart_type": "implant"},
    {"id": 16, "name": "Implant Placement",              "code": "0902", "chart_type": "implant"},
    {"id": 17, "name": "Hygienist Treatment",            "code": "1001", "chart_type": "hygiene"},
    {"id": 18, "name": "Periodontal Treatment",          "code": "1002", "chart_type": "hygiene"},
    {"id": 19, "name": "Fissure Sealant",                "code": "0151", "chart_type": "preventive"},
    {"id": 20, "name": "Emergency Appointment",          "code": "9901", "chart_type": "emergency"},
]

PRIVATE_PRICES = {
    1: (55, 85),    2: (70, 110),   3: (25, 45),    4: (120, 180),
    5: (150, 220),  6: (90, 140),   7: (180, 280),  8: (450, 650),
    9: (550, 850),  10: (650, 950), 11: (750, 1100), 12: (1200, 1800),
    13: (280, 380), 14: (480, 680), 15: (150, 250), 16: (2000, 3500),
    17: (75, 120),  18: (120, 200), 19: (45, 75),   20: (85, 150),
}

NHS_BANDS = {1: 0.0, 2: 23.80, 3: 65.20}


# ══════════════════════════════════════════════════════════════════════════════
# PER-TENANT REFERENCE DATA
# ══════════════════════════════════════════════════════════════════════════════

TENANT1_REF = {
    "practice": {
        "id": "prac-001",
        "name": "Smile Group",
        "email_address": "info@smilegroup.co.uk",
        "phone_number": 1865000000,
        "address_line_1": "14 High Street",
        "address_line_2": None,
        "postcode": "OX1 4AA",
        "website": "https://smilegroup.co.uk",
        "logo_url": "https://smilegroup.co.uk/logo.png",
        "slug": "smile-group",
        "time_zone": "Europe/London",
        "patient_email_address": "patients@smilegroup.co.uk",
        "custom_patient_field_label_1": None,
        "custom_patient_field_label_2": None,
        "medical_history_expiry_days": 365,
        "nhs": True,
        "oh_mon_open": "09:00", "oh_mon_close": "17:30",
        "oh_tues_open": "09:00", "oh_tues_close": "17:30",
        "oh_wed_open": "09:00", "oh_wed_close": "17:30",
        "oh_thur_open": "09:00", "oh_thur_close": "17:30",
        "oh_fri_open": "09:00", "oh_fri_close": "17:00",
        "oh_sat_open": None, "oh_sat_close": None,
        "oh_sun_open": None, "oh_sun_close": None,
    },
    "sites": [
        {
            "id": "site-hs-001", "practice_id": "prac-001", "name": "High Street",
            "active": True, "address_line_1": "14 High Street", "address_line_2": None,
            "town": "Oxford", "postcode": "OX1 4AA", "phone": "01865 123456",
            "email": "highstreet@smilegroup.co.uk", "website": "https://smilegroup.co.uk",
            "logo_url": "https://smilegroup.co.uk/logo.png", "default_payment_plan_id": 2,
            "monday_open": "09:00", "monday_close": "17:30",
            "tuesday_open": "09:00", "tuesday_close": "17:30",
            "wednesday_open": "09:00", "wednesday_close": "17:30",
            "thursday_open": "09:00", "thursday_close": "17:30",
            "friday_open": "09:00", "friday_close": "17:00",
        },
        {
            "id": "site-rv-002", "practice_id": "prac-001", "name": "Riverside",
            "active": True, "address_line_1": "10 Riverside Walk", "address_line_2": None,
            "town": "Oxford", "postcode": "OX2 6HH", "phone": "01865 234567",
            "email": "riverside@smilegroup.co.uk", "website": "https://smilegroup.co.uk",
            "logo_url": "https://smilegroup.co.uk/logo.png", "default_payment_plan_id": 2,
            "monday_open": "09:00", "monday_close": "17:30",
            "tuesday_open": "09:00", "tuesday_close": "17:30",
            "wednesday_open": "09:00", "wednesday_close": "17:30",
            "thursday_open": "09:00", "thursday_close": "17:30",
            "friday_open": "09:00", "friday_close": "17:00",
        },
        {
            "id": "site-ng-003", "practice_id": "prac-001", "name": "Northgate",
            "active": True, "address_line_1": "45 Northgate", "address_line_2": None,
            "town": "Oxford", "postcode": "OX3 9BB", "phone": "01865 345678",
            "email": "northgate@smilegroup.co.uk", "website": "https://smilegroup.co.uk",
            "logo_url": "https://smilegroup.co.uk/logo.png", "default_payment_plan_id": 2,
            "monday_open": "09:00", "monday_close": "17:30",
            "tuesday_open": "09:00", "tuesday_close": "17:30",
            "wednesday_open": "09:00", "wednesday_close": "17:30",
            "thursday_open": "09:00", "thursday_close": "17:30",
            "friday_open": "09:00", "friday_close": "17:00",
        },
    ],
    "users": [
        {"id": 1, "first_name": "Admin",  "last_name": "User",   "email": "admin@smilegroup.co.uk",   "role": "admin"},
        {"id": 2, "first_name": "Amir",   "last_name": "Ahmed",  "email": "a.ahmed@smilegroup.co.uk", "role": "dentist"},
        {"id": 3, "first_name": "Li",     "last_name": "Chen",   "email": "l.chen@smilegroup.co.uk",  "role": "dentist"},
        {"id": 4, "first_name": "Priya",  "last_name": "Patel",  "email": "p.patel@smilegroup.co.uk", "role": "dentist"},
        {"id": 5, "first_name": "Sarah",  "last_name": "Morris", "email": "s.morris@smilegroup.co.uk","role": "hygienist"},
        {"id": 6, "first_name": "James",  "last_name": "Wright", "email": "j.wright@smilegroup.co.uk","role": "dentist"},
        {"id": 7, "first_name": "Claire", "last_name": "Booth",  "email": "c.booth@smilegroup.co.uk", "role": "receptionist"},
        {"id": 8, "first_name": "Marcus", "last_name": "Hall",   "email": "m.hall@smilegroup.co.uk",  "role": "receptionist"},
    ],
    "practitioners": [
        {"id": 2, "first_name": "Amir",  "last_name": "Ahmed",  "role": "dentist",   "site_id": "site-hs-001", "user_id": 2, "active": True},
        {"id": 3, "first_name": "Li",    "last_name": "Chen",   "role": "dentist",   "site_id": "site-rv-002", "user_id": 3, "active": True},
        {"id": 4, "first_name": "Priya", "last_name": "Patel",  "role": "dentist",   "site_id": "site-hs-001", "user_id": 4, "active": True},
        {"id": 5, "first_name": "Sarah", "last_name": "Morris", "role": "hygienist", "site_id": "site-rv-002", "user_id": 5, "active": True},
        {"id": 6, "first_name": "James", "last_name": "Wright", "role": "dentist",   "site_id": "site-ng-003", "user_id": 6, "active": False},
    ],
    "payment_plans": [
        {"id": 1, "name": "NHS",         "nhs": True,  "monthly_charge": "0.00",  "dentist_recall_interval": 6,  "hygienist_recall_interval": 6,  "exam_duration": 20, "scale_polish_duration": 30},
        {"id": 2, "name": "Private",     "nhs": False, "monthly_charge": "0.00",  "dentist_recall_interval": 12, "hygienist_recall_interval": 6,  "exam_duration": 30, "scale_polish_duration": 45},
        {"id": 3, "name": "Care Plan",   "nhs": False, "monthly_charge": "14.99", "dentist_recall_interval": 9,  "hygienist_recall_interval": 6,  "exam_duration": 30, "scale_polish_duration": 45},
        {"id": 4, "name": "Premium Plan","nhs": False, "monthly_charge": "24.99", "dentist_recall_interval": 6,  "hygienist_recall_interval": 3,  "exam_duration": 45, "scale_polish_duration": 60},
    ],
    "contracts": [
        {"id": "con-hs-001", "active": True, "contract_number": "16S-HS001", "end_date": "2027-03-31", "nhs_location_id": "Y01", "nhs_site_id": "FW001", "pds_plus": False, "site_id": "site-hs-001", "start_date": "2024-04-01", "target": "500.00", "uda_value": "28.00", "uoa_target": "0.00", "uoa_value": "0.00", "created_at": "2024-04-01T00:00:00.000+00:00", "updated_at": "2025-04-01T00:00:00.000+00:00"},
        {"id": "con-rv-002", "active": True, "contract_number": "16S-RV002", "end_date": "2027-03-31", "nhs_location_id": "Y01", "nhs_site_id": "FW002", "pds_plus": False, "site_id": "site-rv-002", "start_date": "2024-04-01", "target": "400.00", "uda_value": "28.00", "uoa_target": "0.00", "uoa_value": "0.00", "created_at": "2024-04-01T00:00:00.000+00:00", "updated_at": "2025-04-01T00:00:00.000+00:00"},
        {"id": "con-ng-003", "active": True, "contract_number": "16S-NG003", "end_date": "2027-03-31", "nhs_location_id": "Y01", "nhs_site_id": "FW003", "pds_plus": False, "site_id": "site-ng-003", "start_date": "2024-04-01", "target": "350.00", "uda_value": "28.00", "uoa_target": "0.00", "uoa_value": "0.00", "created_at": "2024-04-01T00:00:00.000+00:00", "updated_at": "2025-04-01T00:00:00.000+00:00"},
    ],
    "sundries": [
        {"id": "sun-001", "name": "Disposable Bib", "nickname": "Bib",    "price": "0.25", "site_id": "site-hs-001"},
        {"id": "sun-002", "name": "Gloves (pair)",  "nickname": "Gloves", "price": "0.30", "site_id": "site-hs-001"},
        {"id": "sun-003", "name": "Dental Floss",   "nickname": "Floss",  "price": "1.50", "site_id": "site-hs-001"},
        {"id": "sun-004", "name": "Mouthwash",      "nickname": "MW",     "price": "2.99", "site_id": "site-rv-002"},
        {"id": "sun-005", "name": "Toothbrush",     "nickname": "TBrush", "price": "3.99", "site_id": "site-ng-003"},
    ],
}

TENANT2_REF = {
    "practice": {
        "id": "prac-002",
        "name": "Bright Dental",
        "email_address": "info@brightdental.co.uk",
        "phone_number": 1273000000,
        "address_line_1": "55 Kings Road",
        "address_line_2": None,
        "postcode": "BN1 1NA",
        "website": "https://brightdental.co.uk",
        "logo_url": "https://brightdental.co.uk/logo.png",
        "slug": "bright-dental",
        "time_zone": "Europe/London",
        "patient_email_address": "patients@brightdental.co.uk",
        "custom_patient_field_label_1": None,
        "custom_patient_field_label_2": None,
        "medical_history_expiry_days": 365,
        "nhs": True,
        "oh_mon_open": "08:30", "oh_mon_close": "17:00",
        "oh_tues_open": "08:30", "oh_tues_close": "17:00",
        "oh_wed_open": "08:30", "oh_wed_close": "17:00",
        "oh_thur_open": "08:30", "oh_thur_close": "17:00",
        "oh_fri_open": "08:30", "oh_fri_close": "16:30",
        "oh_sat_open": "09:00", "oh_sat_close": "13:00",
        "oh_sun_open": None, "oh_sun_close": None,
    },
    "sites": [
        {
            "id": "site-br-001", "practice_id": "prac-002", "name": "Kings Road",
            "active": True, "address_line_1": "55 Kings Road", "address_line_2": None,
            "town": "Brighton", "postcode": "BN1 1NA", "phone": "01273 100200",
            "email": "kingsroad@brightdental.co.uk", "website": "https://brightdental.co.uk",
            "logo_url": "https://brightdental.co.uk/logo.png", "default_payment_plan_id": 1,
            "monday_open": "08:30", "monday_close": "17:00",
            "tuesday_open": "08:30", "tuesday_close": "17:00",
            "wednesday_open": "08:30", "wednesday_close": "17:00",
            "thursday_open": "08:30", "thursday_close": "17:00",
            "friday_open": "08:30", "friday_close": "16:30",
        },
        {
            "id": "site-br-002", "practice_id": "prac-002", "name": "Seven Dials",
            "active": True, "address_line_1": "12 Seven Dials", "address_line_2": None,
            "town": "Brighton", "postcode": "BN1 3JS", "phone": "01273 200300",
            "email": "sevendials@brightdental.co.uk", "website": "https://brightdental.co.uk",
            "logo_url": "https://brightdental.co.uk/logo.png", "default_payment_plan_id": 1,
            "monday_open": "09:00", "monday_close": "17:00",
            "tuesday_open": "09:00", "tuesday_close": "17:00",
            "wednesday_open": "09:00", "wednesday_close": "17:00",
            "thursday_open": "09:00", "thursday_close": "17:00",
            "friday_open": "09:00", "friday_close": "16:00",
        },
    ],
    "users": [
        {"id": 1, "first_name": "Admin",    "last_name": "User",     "email": "admin@brightdental.co.uk",   "role": "admin"},
        {"id": 2, "first_name": "Rachel",   "last_name": "Green",    "email": "r.green@brightdental.co.uk", "role": "dentist"},
        {"id": 3, "first_name": "Daniel",   "last_name": "Foster",   "email": "d.foster@brightdental.co.uk","role": "dentist"},
        {"id": 4, "first_name": "Nadia",    "last_name": "Hassan",   "email": "n.hassan@brightdental.co.uk","role": "hygienist"},
        {"id": 5, "first_name": "Callum",   "last_name": "Reid",     "email": "c.reid@brightdental.co.uk",  "role": "receptionist"},
    ],
    "practitioners": [
        {"id": 2, "first_name": "Rachel", "last_name": "Green",  "role": "dentist",   "site_id": "site-br-001", "user_id": 2, "active": True},
        {"id": 3, "first_name": "Daniel", "last_name": "Foster", "role": "dentist",   "site_id": "site-br-002", "user_id": 3, "active": True},
        {"id": 4, "first_name": "Nadia",  "last_name": "Hassan", "role": "hygienist", "site_id": "site-br-001", "user_id": 4, "active": True},
    ],
    "payment_plans": [
        {"id": 1, "name": "NHS",     "nhs": True,  "monthly_charge": "0.00",  "dentist_recall_interval": 6,  "hygienist_recall_interval": 6,  "exam_duration": 20, "scale_polish_duration": 30},
        {"id": 2, "name": "Private", "nhs": False, "monthly_charge": "0.00",  "dentist_recall_interval": 12, "hygienist_recall_interval": 6,  "exam_duration": 30, "scale_polish_duration": 45},
    ],
    "contracts": [
        {"id": "con-br-001", "active": True, "contract_number": "16S-BR001", "end_date": "2027-03-31", "nhs_location_id": "Y02", "nhs_site_id": "BN001", "pds_plus": False, "site_id": "site-br-001", "start_date": "2024-04-01", "target": "300.00", "uda_value": "28.00", "uoa_target": "0.00", "uoa_value": "0.00", "created_at": "2024-04-01T00:00:00.000+00:00", "updated_at": "2025-04-01T00:00:00.000+00:00"},
        {"id": "con-br-002", "active": True, "contract_number": "16S-BR002", "end_date": "2027-03-31", "nhs_location_id": "Y02", "nhs_site_id": "BN002", "pds_plus": False, "site_id": "site-br-002", "start_date": "2024-04-01", "target": "250.00", "uda_value": "28.00", "uoa_target": "0.00", "uoa_value": "0.00", "created_at": "2024-04-01T00:00:00.000+00:00", "updated_at": "2025-04-01T00:00:00.000+00:00"},
    ],
    "sundries": [
        {"id": "sun-001", "name": "Disposable Bib",  "nickname": "Bib",   "price": "0.20", "site_id": "site-br-001"},
        {"id": "sun-002", "name": "Interdental Brush","nickname": "IDB",   "price": "1.20", "site_id": "site-br-001"},
        {"id": "sun-003", "name": "Whitening Strips", "nickname": "Strips","price": "12.99","site_id": "site-br-002"},
    ],
}


# ══════════════════════════════════════════════════════════════════════════════
# DATA GENERATORS  (all take ref= dict; no module-level globals)
# ══════════════════════════════════════════════════════════════════════════════

def _iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.000+00:00")

def _rand_date_offset(base, min_days, max_days):
    return base + timedelta(days=random.randint(min_days, max_days))


def gen_patients(n, ref):
    first_names = [
        "James", "Emma", "Oliver", "Sophia", "William", "Isabella", "Benjamin", "Charlotte",
        "Elijah", "Amelia", "Lucas", "Mia", "Mason", "Harper", "Ethan", "Evelyn",
        "Mohammed", "Fatima", "Aisha", "Yusuf", "Zara", "Ibrahim", "Ali", "Sara",
        "George", "Alice", "Harry", "Rose", "Jack", "Grace", "Thomas", "Lucy",
        "Liam", "Abigail", "Noah", "Emily", "Aiden", "Elizabeth", "Logan", "Avery",
        "Callum", "Isla", "Finn", "Niamh", "Declan", "Siobhan", "Ronan", "Aoife",
    ]
    last_names = [
        "Smith", "Jones", "Williams", "Taylor", "Brown", "Davies", "Evans", "Wilson",
        "Thomas", "Roberts", "Johnson", "Lewis", "Walker", "Robinson", "Wood", "Thompson",
        "Patel", "Ahmed", "Khan", "Singh", "Ali", "Hussain", "Rahman", "Shah",
        "White", "Watson", "Jackson", "Wright", "Green", "Harris", "Martin", "King",
        "Clarke", "Scott", "Turner", "Hill", "Moore", "Anderson", "Mitchell", "Carter",
    ]
    streets = ["High St", "Church Rd", "Station Rd", "Park Ave", "Victoria Rd",
               "Mill Lane", "Orchard Way", "Meadow Close", "The Green", "Manor Drive"]

    sites        = ref["sites"]
    practitioners = ref["practitioners"]
    payment_plans = ref["payment_plans"]
    town          = sites[0].get("town", "London")

    dentists   = [p for p in practitioners if p["role"] == "dentist"]
    hygienists = [p for p in practitioners if p["role"] == "hygienist"]

    patients = []
    for i in range(1, n + 1):
        fn  = random.choice(first_names)
        ln  = random.choice(last_names)
        dob = date(random.randint(1944, 2010), random.randint(1, 12), random.randint(1, 28))
        site      = random.choice(sites)
        pract     = random.choice(dentists)
        hygienist = random.choice(hygienists) if hygienists else pract
        pp        = random.choice(payment_plans)
        created_at = datetime.now() - timedelta(days=random.randint(60, 2000))
        patients.append({
            "id": i,
            "account_id": i,
            "active": random.random() > 0.04,
            "first_name": fn,
            "last_name": ln,
            "date_of_birth": dob.isoformat(),
            "gender": random.choice([True, False]),
            "email_address": f"{fn.lower()}.{ln.lower()}{i}@example.com",
            "mobile_phone": f"07{random.randint(700_000_000, 799_999_999)}",
            "home_phone": None,
            "address_line_1": f"{random.randint(1, 200)} {random.choice(streets)}",
            "address_line_2": None,
            "town": town,
            "county": site.get("town", ""),
            "postcode": site["postcode"],
            "payment_plan_id": pp["id"],
            "dentist_id": pract["id"],
            "hygienist_id": hygienist["id"],
            "site_id": site["id"],
            "dentist_recall_interval": pp["dentist_recall_interval"],
            "hygienist_recall_interval": pp["hygienist_recall_interval"],
            "dentist_recall_date": _rand_date_offset(date.today(), -180, 540).isoformat(),
            "hygienist_recall_date": _rand_date_offset(date.today(), -180, 540).isoformat(),
            "nhs_number": f"{random.randint(100,999)} {random.randint(100,999)} {random.randint(1000,9999)}" if pp["nhs"] else None,
            "ni_number": None,
            "marketing": random.random() > 0.35,
            "medical_alert": random.random() > 0.88,
            "medical_alert_text": "Penicillin allergy" if random.random() > 0.95 else None,
            "occupation": random.choice(["Teacher", "Nurse", "Engineer", "Retired", "Student", "Manager", None]),
            "created_at": _iso(created_at),
            "updated_at": _iso(created_at + timedelta(days=random.randint(0, 200))),
        })
    return patients


def gen_appointments(patients, n, ref):
    states  = ["Arrived", "Completed", "Did Not Attend", "Cancelled", "Booked", "In Chair"]
    weights = [0.03, 0.68, 0.06, 0.08, 0.12, 0.03]
    reasons  = [
        "Examination", "Scale and Polish", "Treatment",
        "Emergency", "Review", "New Patient Examination",
    ]
    r_weights = [38, 28, 20, 4, 4, 6]
    practitioners = ref["practitioners"]
    patient_map   = {p["id"]: p for p in patients}
    cancellation_reason_ids = {
        "Patient request": 1, "Practitioner unavailable": 2, "Emergency": 3
    }
    appointments = []
    for i in range(1, n + 1):
        patient  = random.choice(patients)
        pract    = random.choice(practitioners)
        apt_dt   = datetime.now() - timedelta(days=random.randint(-90, 730))
        duration = random.choice([15, 20, 30, 40, 45, 60, 75, 90])
        state    = random.choices(states, weights=weights)[0]
        if apt_dt > datetime.now():
            state = random.choice(["Booked", "Booked", "Booked", "Cancelled"])
        waiting_mins    = random.randint(0, 20) if state == "Completed" else 0
        in_surgery_mins = duration + random.randint(-5, 10) if state == "Completed" else 0

        # Derive status timestamps from state
        arrived_dt    = None
        in_surgery_dt = None
        completed_dt  = None
        cancelled_dt  = None
        dna_dt        = None
        confirmed_dt  = None
        pending_dt    = apt_dt - timedelta(days=random.randint(1, 45))

        if state == "Completed":
            arrived_dt    = apt_dt - timedelta(minutes=waiting_mins)
            in_surgery_dt = apt_dt
            completed_dt  = apt_dt + timedelta(minutes=in_surgery_mins)
        elif state == "Arrived":
            arrived_dt = apt_dt - timedelta(minutes=random.randint(1, 15))
        elif state == "In Chair":
            arrived_dt    = apt_dt - timedelta(minutes=random.randint(5, 20))
            in_surgery_dt = apt_dt
        elif state == "Cancelled":
            cancelled_dt = apt_dt - timedelta(days=random.randint(1, 7))
        elif state == "Did Not Attend":
            dna_dt = apt_dt + timedelta(minutes=random.randint(10, 30))

        if state in ("Booked", "Completed", "Arrived", "In Chair") and random.random() > 0.3:
            confirmed_dt = apt_dt - timedelta(days=random.randint(1, 3))

        cancel_reason_str = None
        cancel_reason_id  = None
        if state == "Cancelled":
            cancel_reason_str = random.choice(["Patient request", "Practitioner unavailable", "Emergency", None])
            cancel_reason_id  = cancellation_reason_ids.get(cancel_reason_str)

        appointments.append({
            "id": i,
            "uuid": str(_uuid_mod.uuid5(_uuid_mod.NAMESPACE_OID, f"appt-{i}")),
            "appointment_cancellation_reason_id": cancel_reason_id,
            "patient_id": patient["id"],
            "patient_name": f"{patient['first_name']} {patient['last_name']}",
            "patient_image_url": None,
            "practitioner_id": pract["id"],
            "user_id": pract.get("user_id", 1),
            "payment_plan_id": patient["payment_plan_id"],
            "site_id": patient["site_id"],
            "room_id": f"room-{random.randint(1, 3)}",
            "reason": random.choices(reasons, weights=r_weights)[0],
            "booked_via_api": random.random() < 0.18,
            "start_time": _iso(apt_dt),
            "finish_time": _iso(apt_dt + timedelta(minutes=duration)),
            "duration": duration,
            "state": state,
            "treatment_description": None,
            "did_not_attend": state == "Did Not Attend",
            "waiting_time": waiting_mins,
            "in_surgery_time": in_surgery_mins,
            "cancellation_reason": cancel_reason_str,
            "notes": None,
            "pending_at":       _iso(pending_dt),
            "confirmed_at":     _iso(confirmed_dt)  if confirmed_dt  else None,
            "arrived_at":       _iso(arrived_dt)    if arrived_dt    else None,
            "in_surgery_at":    _iso(in_surgery_dt) if in_surgery_dt else None,
            "completed_at":     _iso(completed_dt)  if completed_dt  else None,
            "cancelled_at":     _iso(cancelled_dt)  if cancelled_dt  else None,
            "did_not_attend_at":_iso(dna_dt)        if dna_dt        else None,
            "created_at": _iso(pending_dt),
            "updated_at": _iso(apt_dt),
        })
    return appointments


def gen_invoices_and_items(appointments, patients, ref):
    payment_plans = ref["payment_plans"]
    patient_map   = {p["id"]: p for p in patients}
    plan_map      = {pp["id"]: pp for pp in payment_plans}

    invoices      = []
    invoice_items = []
    inv_id  = 1
    item_id = 1

    for apt in [a for a in appointments if a["state"] == "Completed"]:
        patient  = patient_map.get(apt["patient_id"])
        if not patient:
            continue
        pp     = plan_map.get(patient["payment_plan_id"])
        is_nhs = pp["nhs"] if pp else False
        apt_dt = datetime.fromisoformat(apt["start_time"].replace("+00:00", ""))

        chosen    = random.sample(TREATMENTS, random.randint(1, 3))
        total     = 0.0
        nhs_total = 0.0

        for t in chosen:
            if is_nhs:
                band      = random.choices([1, 2, 3], weights=[0.25, 0.45, 0.30])[0]
                price     = NHS_BANDS[band]
                nhs_charge = price
            else:
                lo, hi    = PRIVATE_PRICES.get(t["id"], (50, 200))
                price     = round(random.uniform(lo, hi), 2)
                nhs_charge = 0.0
            total     += price
            nhs_total += nhs_charge
            invoice_items.append({
                "id": item_id,
                "invoice_id": inv_id,
                "patient_id": apt["patient_id"],
                "practitioner_id": apt["practitioner_id"],
                "site_id": apt["site_id"],
                "treatment_id": t["id"],
                "treatment_name": t["name"],
                "treatment_code": t["code"],
                "quantity": 1,
                "price": f"{price:.2f}",
                "nhs_charge": f"{nhs_charge:.2f}",
                "created_at": _iso(apt_dt),
                "updated_at": _iso(apt_dt),
            })
            item_id += 1

        paid = random.random() > 0.09
        invoices.append({
            "id": inv_id,
            "patient_id": apt["patient_id"],
            "account_id": apt["patient_id"],
            "site_id": apt["site_id"],
            "user_id": apt["practitioner_id"],
            "appointment_id": apt["id"],
            "amount": f"{total:.2f}",
            "amount_outstanding": "0.00" if paid else f"{total:.2f}",
            "nhs_amount": f"{nhs_total:.2f}" if is_nhs else None,
            "dated_on": apt_dt.date().isoformat(),
            "due_on": (apt_dt.date() + timedelta(days=7)).isoformat(),
            "paid": paid,
            "paid_on": apt_dt.date().isoformat() if paid else None,
            "status": "Paid" if paid else "Outstanding",
            "reference": f"INV-{inv_id:06d}",
            "footnote": None,
            "sent_at": None,
            "created_at": _iso(apt_dt),
            "updated_at": _iso(apt_dt),
        })
        inv_id += 1

    return invoices, invoice_items


def gen_payments(invoices, patients, ref):
    payment_plans = ref["payment_plans"]
    patient_map   = {p["id"]: p for p in patients}
    plan_map      = {pp["id"]: pp for pp in payment_plans}
    methods       = ["Cash", "Card", "Bank Transfer", "Direct Debit", "Cheque"]
    weights       = [0.10, 0.65, 0.15, 0.08, 0.02]
    payments = []
    pay_id = 1
    for inv in [i for i in invoices if i["paid"]]:
        patient = patient_map.get(inv["patient_id"])
        if not patient:
            continue
        pp    = plan_map.get(patient["payment_plan_id"])
        dated = datetime.fromisoformat(inv["dated_on"])
        payments.append({
            "id": pay_id,
            "account_id": inv["account_id"],
            "patient_id": inv["patient_id"],
            "site_id": inv["site_id"],
            "payment_plan_id": pp["id"] if pp else None,
            "practitioner_id": inv["user_id"],
            "user_id": inv["user_id"],
            "amount": inv["amount"],
            "amount_unexplained": "0.00",
            "dated_on": inv["paid_on"],
            "method": random.choices(methods, weights=weights)[0],
            "reference": f"PAY-{pay_id:06d}",
            "status": "Completed",
            "deleted": False,
            "fully_explained": True,
            "transaction_number": str(random.randint(100_000_000, 999_999_999)),
            "created_at": _iso(dated),
            "updated_at": _iso(dated),
        })
        pay_id += 1
    return payments


def gen_treatment_plans(patients, n, ref):
    practitioners = ref["practitioners"]
    statuses      = ["Draft", "Presented", "Accepted", "Partially Accepted", "Declined", "Completed"]
    weights       = [0.05, 0.12, 0.42, 0.15, 0.08, 0.18]
    dentists      = [p for p in practitioners if p["role"] == "dentist"]
    plans = []
    for i in range(1, n + 1):
        patient    = random.choice(patients)
        pract      = random.choice(dentists)
        created_at = datetime.now() - timedelta(days=random.randint(10, 730))
        status     = random.choices(statuses, weights=weights)[0]
        is_nhs     = random.random() > 0.55
        chosen     = random.sample(TREATMENTS, random.randint(1, 5))
        private_value = sum(
            round(random.uniform(*PRIVATE_PRICES.get(t["id"], (50, 200))), 2)
            for t in chosen if not is_nhs
        )
        nhs_uda = round(random.uniform(1, 3), 2) if is_nhs else 0.0
        plans.append({
            "id": i,
            "patient_id": patient["id"],
            "patient_name": f"{patient['first_name']} {patient['last_name']}",
            "practitioner_id": pract["id"],
            "site_id": patient["site_id"],
            "status": status,
            "nhs": is_nhs,
            "nhs_uda_value": f"{nhs_uda:.2f}",
            "nhs_completed_uda_value": f"{nhs_uda:.2f}" if status == "Completed" else "0.00",
            "private_treatment_value": f"{private_value:.2f}",
            "created_at": _iso(created_at),
            "updated_at": _iso(created_at + timedelta(days=random.randint(0, 60))),
        })
    return plans


def gen_treatment_plan_items(treatment_plans, ref):
    practitioners = ref["practitioners"]
    pract_map     = {p["id"]: p for p in practitioners}
    items  = []
    item_id = 1
    for plan in treatment_plans:
        chosen     = random.sample(TREATMENTS, random.randint(1, 5))
        created_at = datetime.fromisoformat(plan["created_at"].replace("+00:00", ""))
        for t in chosen:
            is_nhs = plan["nhs"]
            price  = NHS_BANDS[random.choice([1, 2, 3])] if is_nhs else round(random.uniform(*PRIVATE_PRICES.get(t["id"], (50, 200))), 2)
            items.append({
                "id": item_id,
                "treatment_plan_id": plan["id"],
                "patient_id": plan["patient_id"],
                "practitioner_id": plan["practitioner_id"],
                "site_id": plan["site_id"],
                "treatment_id": t["id"],
                "treatment_name": t["name"],
                "treatment_code": t["code"],
                "quantity": 1,
                "price": f"{price:.2f}",
                "duration": random.choice([15, 20, 30, 45, 60]),
                "status": plan["status"],
                "created_at": _iso(created_at),
                "updated_at": _iso(created_at),
            })
            item_id += 1
    return items


def gen_recalls(patients, ref):
    recalls   = []
    recall_id = 1
    for p in patients:
        for recall_type, date_field, pract_field in [
            ("dentist",   "dentist_recall_date",   "dentist_id"),
            ("hygienist", "hygienist_recall_date",  "hygienist_id"),
        ]:
            recall_date  = date.fromisoformat(p[date_field])
            overdue_days = (date.today() - recall_date).days
            times_contacted = random.randint(0, 4) if overdue_days > 0 else 0
            # first_reminder_sent_at: set when a reminder has been dispatched (overdue + contacted,
            # or sent in advance for upcoming recalls ~65% of the time)
            if times_contacted > 0:
                sent_dt = datetime.combine(recall_date - timedelta(days=random.randint(7, 21)), datetime.min.time())
                first_reminder_sent_at = _iso(sent_dt)
            elif overdue_days <= 0 and random.random() < 0.65:
                sent_dt = datetime.combine(recall_date - timedelta(days=random.randint(14, 42)), datetime.min.time())
                first_reminder_sent_at = _iso(sent_dt)
            else:
                first_reminder_sent_at = None
            recalls.append({
                "id": recall_id,
                "patient_id": p["id"],
                "patient_name": f"{p['first_name']} {p['last_name']}",
                "site_id": p["site_id"],
                "practitioner_id": p[pract_field],
                "recall_type": recall_type,
                "due_date": recall_date.isoformat(),
                "days_overdue": max(0, overdue_days),
                "times_contacted": times_contacted,
                "first_reminder_sent_at": first_reminder_sent_at,
                "status": "Overdue" if overdue_days > 0 else "Due",
                "created_at": _iso(datetime.now() - timedelta(days=abs(overdue_days) + p[f"{recall_type}_recall_interval"] * 30)),
                "updated_at": _iso(datetime.now() - timedelta(days=random.randint(0, 30))),
            })
            recall_id += 1
    return recalls


def gen_diary_entries(n_weeks, ref):
    practitioners = ref["practitioners"]
    entries  = []
    entry_id = 1
    start    = date.today() - timedelta(weeks=n_weeks)
    for pract in practitioners:
        current = start
        while current <= date.today():
            if current.weekday() < 5:
                for start_hour, pm in [(9, False), (13, True)]:
                    if pm and random.random() > 0.7:
                        continue
                    session_start = datetime(current.year, current.month, current.day, start_hour, 30 if pm else 0)
                    duration    = random.choice([120, 150, 180, 210, 240] if not pm else [120, 150, 180, 210])
                    break_count = random.randint(0, 2)
                    break_mins  = break_count * 15
                    entries.append({
                        "id": entry_id,
                        "practitioner_id": pract["id"],
                        "site_id": pract["site_id"],
                        "date": current.isoformat(),
                        "start_time": _iso(session_start),
                        "end_time": _iso(session_start + timedelta(minutes=duration + break_mins)),
                        "session_duration": duration,
                        "available_clinical_mins": duration,
                        "break_count": break_count,
                        "total_break_mins": break_mins,
                        "created_at": _iso(session_start - timedelta(days=7)),
                        "updated_at": _iso(session_start),
                    })
                    entry_id += 1
            current += timedelta(days=1)
    return entries


def gen_fees(ref):
    payment_plans = ref["payment_plans"]
    fees = []
    for pp in payment_plans:
        for t in TREATMENTS:
            if pp["nhs"]:
                price = f"{NHS_BANDS[random.choice([1, 2, 3])]:.2f}"
            else:
                lo, hi = PRIVATE_PRICES.get(t["id"], (50, 100))
                price  = f"{round(random.uniform(lo, hi), 2):.2f}"
            fees.append({
                "fee_id": f"fee-{pp['id']}-{t['id']}",
                "payment_plan_id": pp["id"],
                "treatment_id": t["id"],
                "multiple_pricing": False,
                "duration_one": random.choice([20, 30, 45, 60]),
                "duration_two": None, "duration_three": None,
                "duration_four": None, "duration_five": None,
                "price_one": price,
                "price_two": None, "price_three": None,
                "price_four": None, "price_five": None,
            })
    return fees


def gen_patient_stats(patients, appointments, invoices, payments):
    today    = date.today().isoformat()
    inv_map  = {}
    for i in invoices:
        inv_map.setdefault(i["patient_id"], []).append(i)
    pay_map  = {}
    for p in payments:
        pay_map.setdefault(p["patient_id"], []).append(p)
    apt_map  = {}
    for a in appointments:
        apt_map.setdefault(a["patient_id"], []).append(a)

    stats = []
    for p in patients:
        pt_appts = sorted(apt_map.get(p["id"], []), key=lambda a: a["start_time"])
        past     = [a for a in pt_appts if a["start_time"][:10] < today]
        future   = [a for a in pt_appts if a["start_time"][:10] >= today]
        total_invoiced = sum(float(i["amount"]) for i in inv_map.get(p["id"], []))
        total_paid     = sum(float(pay["amount"]) for pay in pay_map.get(p["id"], []))
        nhs_exempt     = random.choice([0, 0, 0, 1, 2]) if p.get("payment_plan_id") == 1 else 0
        stats.append({
            "patient_id": p["id"],
            "last_appointment_date":          past[-1]["start_time"][:10] if past else None,
            "last_exam_date":                 past[-1]["start_time"][:10] if past else None,
            "last_scale_and_polish_date":     past[-1]["start_time"][:10] if past else None,
            "next_appointment_date":          future[0]["start_time"][:10] if future else None,
            "next_exam_date":                 future[0]["start_time"][:10] if future else None,
            "next_scale_and_polish_date":     future[0]["start_time"][:10] if future else None,
            "created_at":                     p["created_at"],
            "updated_at":                     p["updated_at"],
            "total_paid":                     f"{total_paid:.2f}",
            "total_invoiced":                 f"{total_invoiced:.2f}",
            "last_fta_appointment_date":      None,
            "first_appointment_date":         past[0]["start_time"][:10] if past else None,
            "first_exam_date":                past[0]["start_time"][:10] if past else None,
            "nhs_exemption_code":             nhs_exempt,
            "last_cancelled_appointment_date": None,
        })
    return stats


def gen_payment_explanations(payments, invoices):
    inv_by_patient = {}
    for i in invoices:
        inv_by_patient.setdefault(i["patient_id"], []).append(i)
    explanations = []
    for idx, pay in enumerate(payments, 1):
        inv = next(iter(inv_by_patient.get(pay["patient_id"], [])), None)
        explanations.append({
            "id": idx,
            "amount": pay["amount"],
            "comments": None,
            "invoice_id": inv["id"] if inv else None,
            "invoice_reference": inv["reference"] if inv else None,
            "payment_id": pay["id"],
            "payment_reference": pay["reference"],
            "user_id": pay.get("user_id", 1),
        })
    return explanations


def gen_payment_allocations(payments, invoice_items, payment_explanations):
    items_by_patient = {}
    for ii in invoice_items:
        items_by_patient.setdefault(ii["patient_id"], []).append(ii)
    exp_by_payment = {e["payment_id"]: e for e in payment_explanations}
    allocations = []
    alloc_id    = 1
    for pay in payments:
        pt_items = items_by_patient.get(pay["patient_id"], [])[:2]
        exp      = exp_by_payment.get(pay["id"])
        for ii in pt_items:
            allocations.append({
                "id": f"alloc-{alloc_id:05d}",
                "amount": ii["price"],
                "created_at": pay["created_at"],
                "description": "Payment allocation",
                "invoice_item_id": str(ii["id"]),
                "patient_id": pay["patient_id"],
                "payment_explanation_id": exp["id"] if exp else None,
                "reversal_of_id": None,
                "transfer_from_id": None, "transfer_from_type": None,
                "transfer_to_id": None,   "transfer_to_type": None,
                "updated_at": pay["updated_at"],
            })
            alloc_id += 1
    return allocations


def gen_nhs_claims(treatment_plans, contracts):
    statuses  = ["submitted", "approved", "rejected", "pending"]
    site_to_contract = {c["site_id"]: c for c in contracts}
    claims    = []
    claim_id  = 1
    for tp in [tp for tp in treatment_plans if tp.get("nhs", False)]:
        contract = site_to_contract.get(tp.get("site_id"), contracts[0] if contracts else None)
        if not contract:
            continue
        uda  = round(random.uniform(1, 3), 2)
        band = random.choice([1, 2, 3])
        claims.append({
            "id": f"nhs-{claim_id:05d}",
            "awarded_uda": uda,
            "approval_date": None,
            "contract_id": contract["id"],
            "claim_status": random.choice(statuses),
            "expected_uda": uda,
            "patient_id": tp["patient_id"],
            "practitioner_id": tp["practitioner_id"],
            "sequence_number": claim_id,
            "site_id": tp["site_id"],
            "status_comments": None,
            "treatment_plan_id": tp["id"],
            "submitted_date": tp["created_at"][:10],
            "patient_charge": NHS_BANDS[band],
            "scot_amount_authorised": 0.0,
            "scot_amount_expected": 0.0,
            "uda_band": band,
            "ortho": 0,
            "continuation_part_number": None,
            "created_at": tp["created_at"],
            "updated_at": tp["updated_at"],
        })
        claim_id += 1
    return claims


def gen_diary_breaks(diary_entries):
    breaks = []
    for entry in diary_entries:
        if entry["break_count"] > 0:
            breaks.append({"practitioner_diary_id": entry["id"], "break_name": "Lunch",     "start_time": "13:00", "end_time": "13:30"})
        if entry["break_count"] > 1:
            breaks.append({"practitioner_diary_id": entry["id"], "break_name": "Tea Break", "start_time": "15:30", "end_time": "15:45"})
    return breaks


def gen_treatment_appointments(treatment_plans, appointments):
    plans_by_patient = {}
    for tp in treatment_plans:
        plans_by_patient.setdefault(tp["patient_id"], []).append(tp)
    ta_list = []
    ta_id   = 1
    for appt in appointments:
        if random.random() > 0.5:
            patient_plans = plans_by_patient.get(appt["patient_id"], [])
            if patient_plans:
                tp = random.choice(patient_plans)
                ta_list.append({
                    "id": f"ta-{ta_id:05d}",
                    "bookable": True,
                    "notes": None,
                    "position": 1,
                    "created_at": appt["created_at"],
                    "updated_at": appt["updated_at"],
                    "appointment_id": appt["id"],
                    "patient_id": appt["patient_id"],
                    "treatment_plan_id": tp["id"],
                })
                ta_id += 1
    return ta_list


def generate_tenant_data(ref, n_patients, n_appointments, n_plans, n_weeks):
    patients               = gen_patients(n_patients, ref)
    appointments           = gen_appointments(patients, n_appointments, ref)
    invoices, invoice_items = gen_invoices_and_items(appointments, patients, ref)
    payments               = gen_payments(invoices, patients, ref)
    treatment_plans        = gen_treatment_plans(patients, n_plans, ref)
    treatment_items        = gen_treatment_plan_items(treatment_plans, ref)
    recalls                = gen_recalls(patients, ref)
    diary_entries          = gen_diary_entries(n_weeks, ref)
    fees                   = gen_fees(ref)
    patient_stats          = gen_patient_stats(patients, appointments, invoices, payments)
    payment_explanations   = gen_payment_explanations(payments, invoices)
    payment_allocations    = gen_payment_allocations(payments, invoice_items, payment_explanations)
    nhs_claims             = gen_nhs_claims(treatment_plans, ref["contracts"])
    diary_breaks           = gen_diary_breaks(diary_entries)
    treatment_appts        = gen_treatment_appointments(treatment_plans, appointments)
    return {
        "practice":            ref["practice"],
        "sites":               ref["sites"],
        "users":               ref["users"],
        "practitioners":       ref["practitioners"],
        "payment_plans":       ref["payment_plans"],
        "contracts":           ref["contracts"],
        "sundries":            ref["sundries"],
        "fees":                fees,
        "patients":            patients,
        "appointments":        appointments,
        "invoices":            invoices,
        "invoice_items":       invoice_items,
        "payments":            payments,
        "treatment_plans":     treatment_plans,
        "treatment_items":     treatment_items,
        "recalls":             recalls,
        "diary_entries":       diary_entries,
        "patient_stats":       patient_stats,
        "payment_explanations": payment_explanations,
        "payment_allocations": payment_allocations,
        "nhs_claims":          nhs_claims,
        "diary_breaks":        diary_breaks,
        "treatment_appts":     treatment_appts,
    }


# ══════════════════════════════════════════════════════════════════════════════
# BUILD ALL DATA AT STARTUP
# ══════════════════════════════════════════════════════════════════════════════

print("Generating test data...")
random.seed(42)
T1 = generate_tenant_data(TENANT1_REF, n_patients=180, n_appointments=1000, n_plans=400, n_weeks=52)
random.seed(123)
T2 = generate_tenant_data(TENANT2_REF, n_patients=60,  n_appointments=300,  n_plans=120, n_weeks=52)

TENANT_DATA = {TENANT1_KEY: T1, TENANT2_KEY: T2}

print(f"  Tenant 1 — Smile Group (Oxford):     {len(T1['patients'])} patients  {len(T1['appointments'])} appointments  {len(T1['invoices'])} invoices  {len(T1['nhs_claims'])} NHS claims")
print(f"  Tenant 2 — Bright Dental (Brighton): {len(T2['patients'])} patients  {len(T2['appointments'])} appointments  {len(T2['invoices'])} invoices  {len(T2['nhs_claims'])} NHS claims")
print()


# ══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def paginate(items):
    page     = int(request.args.get("page", 1))
    per_page = min(int(request.args.get("per_page", 25)), 100)
    total    = len(items)
    start    = (page - 1) * per_page
    return (
        items[start: start + per_page],
        {"total": total, "current_page": page, "total_pages": math.ceil(total / per_page) if total else 0},
    )

def filter_updated_after(items):
    v = request.args.get("updated_after")
    if not v:
        return items
    return [i for i in items if i.get("updated_at", "") >= v]

def add_cors(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    return response

app.after_request(add_cors)


# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — REFERENCE DATA
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/practice")
def practice():
    return jsonify({"practice": g.data["practice"]})

@app.route("/v1/sites")
def sites():
    s = g.data["sites"]
    return jsonify({"sites": s, "meta": {"total": len(s), "current_page": 1, "total_pages": 1}})

@app.route("/v1/users")
def users():
    page_data, meta = paginate(g.data["users"])
    return jsonify({"users": page_data, "meta": meta})

@app.route("/v1/practitioners")
def practitioners():
    result = list(g.data["practitioners"])
    if sid := request.args.get("site_id"):
        result = [p for p in result if p["site_id"] == sid]
    page_data, meta = paginate(result)
    return jsonify({"practitioners": page_data, "meta": meta})

@app.route("/v1/payment_plans")
def payment_plans():
    pp = g.data["payment_plans"]
    return jsonify({"payment_plans": pp, "meta": {"total": len(pp), "current_page": 1, "total_pages": 1}})

@app.route("/v1/treatments")
def treatments():
    return jsonify({"treatments": TREATMENTS, "meta": {"total": len(TREATMENTS), "current_page": 1, "total_pages": 1}})

@app.route("/v1/treatment_categories")
def treatment_categories():
    page_data, meta = paginate(TREATMENT_CATEGORIES)
    return jsonify({"treatment_categories": page_data, "meta": meta})

@app.route("/v1/acquisition_sources")
def acquisition_sources():
    page_data, meta = paginate(ACQUISITION_SOURCES)
    return jsonify({"acquisition_sources": page_data, "meta": meta})

@app.route("/v1/sundries")
def sundries():
    result = list(g.data["sundries"])
    if v := request.args.get("site_id"):
        result = [s for s in result if s["site_id"] == v]
    page_data, meta = paginate(result)
    return jsonify({"sundries": page_data, "meta": meta})

@app.route("/v1/contracts")
def contracts():
    result = list(g.data["contracts"])
    if v := request.args.get("site_id"):
        result = [c for c in result if c["site_id"] == v]
    page_data, meta = paginate(result)
    return jsonify({"contracts": page_data, "meta": meta})

@app.route("/v1/fees")
def fees():
    result = list(g.data["fees"])
    if v := request.args.get("payment_plan_id"): result = [f for f in result if str(f["payment_plan_id"]) == v]
    if v := request.args.get("treatment_id"):    result = [f for f in result if str(f["treatment_id"]) == v]
    page_data, meta = paginate(result)
    return jsonify({"fees": page_data, "meta": meta})

@app.route("/v1/practitioner_diary_breaks")
def diary_breaks():
    result = list(g.data["diary_breaks"])
    if v := request.args.get("practitioner_diary_id"):
        result = [b for b in result if str(b["practitioner_diary_id"]) == v]
    page_data, meta = paginate(result)
    return jsonify({"practitioner_diary_breaks": page_data, "meta": meta})


# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — PATIENTS & ACCOUNTS
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/patients")
def patients():
    result = list(g.data["patients"])
    if v := request.args.get("site_id"): result = [p for p in result if p["site_id"] == v]
    if v := request.args.get("active"):  result = [p for p in result if str(p["active"]).lower() == v.lower()]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"patients": page_data, "meta": meta})

@app.route("/v1/patients/<int:patient_id>")
def patient(patient_id):
    p = next((p for p in g.data["patients"] if p["id"] == patient_id), None)
    if not p:
        return jsonify({"error": "Patient not found"}), 404
    return jsonify({"patient": p})

@app.route("/v1/accounts")
def accounts():
    data         = g.data
    plan_map     = {pp["id"]: pp for pp in data["payment_plans"]}
    inv_by_pat   = {}
    for i in data["invoices"]:
        inv_by_pat.setdefault(i["patient_id"], []).append(i)
    result = []
    for p in data["patients"]:
        inv     = inv_by_pat.get(p["id"], [])
        balance = sum(float(i["amount_outstanding"]) for i in inv)
        pp      = plan_map.get(p["payment_plan_id"], {})
        result.append({
            "id": p["account_id"],
            "patient_id": p["id"],
            "patient_name": f"{p['first_name']} {p['last_name']}",
            "current_balance": f"{-balance:.2f}",
            "opening_balance": "0.00",
            "planned_nhs_treatment_value": f"{round(random.uniform(0, 300), 2):.2f}" if pp.get("nhs") else "0.00",
            "planned_private_treatment_value": f"{round(random.uniform(0, 1500), 2):.2f}" if not pp.get("nhs") else "0.00",
        })
    if pid := request.args.get("patient_id"):
        result = [a for a in result if str(a["patient_id"]) == pid]
    page_data, meta = paginate(result)
    return jsonify({"accounts": page_data, "meta": meta})

@app.route("/v1/patient_stats")
def patient_stats():
    result = list(g.data["patient_stats"])
    if v := request.args.get("patient_id"): result = [s for s in result if str(s["patient_id"]) == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"patient_stats": page_data, "meta": meta})


# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — APPOINTMENTS
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/appointments")
def appointments():
    result = list(g.data["appointments"])
    if v := request.args.get("practitioner_id"): result = [a for a in result if str(a["practitioner_id"]) == v]
    if v := request.args.get("patient_id"):      result = [a for a in result if str(a["patient_id"]) == v]
    if v := request.args.get("site_id"):         result = [a for a in result if a["site_id"] == v]
    if v := request.args.get("state"):           result = [a for a in result if a["state"].lower() == v.lower()]
    if v := request.args.get("after"):           result = [a for a in result if a["start_time"][:10] >= v]
    if v := request.args.get("before"):          result = [a for a in result if a["start_time"][:10] <= v]
    result = filter_updated_after(result)
    result.sort(key=lambda a: a["start_time"])
    page_data, meta = paginate(result)
    return jsonify({"appointments": page_data, "meta": meta})

@app.route("/v1/treatment_appointments")
def treatment_appointments_route():
    result = list(g.data["treatment_appts"])
    if v := request.args.get("patient_id"):        result = [t for t in result if str(t["patient_id"]) == v]
    if v := request.args.get("treatment_plan_id"): result = [t for t in result if str(t["treatment_plan_id"]) == v]
    if v := request.args.get("appointment_id"):    result = [t for t in result if str(t["appointment_id"]) == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"treatment_appointments": page_data, "meta": meta})


# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — INVOICES & PAYMENTS
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/invoices")
def invoices():
    result = list(g.data["invoices"])
    if v := request.args.get("patient_id"):   result = [i for i in result if str(i["patient_id"]) == v]
    if v := request.args.get("site_id"):      result = [i for i in result if i["site_id"] == v]
    if v := request.args.get("dated_after"):  result = [i for i in result if i["dated_on"] >= v]
    if v := request.args.get("dated_before"): result = [i for i in result if i["dated_on"] <= v]
    result = filter_updated_after(result)
    result.sort(key=lambda i: i["dated_on"])
    page_data, meta = paginate(result)
    return jsonify({"invoices": page_data, "meta": meta})

@app.route("/v1/invoice_items")
def invoice_items():
    result = list(g.data["invoice_items"])
    if v := request.args.get("invoice_id"):  result = [i for i in result if str(i["invoice_id"]) == v]
    if v := request.args.get("patient_id"):  result = [i for i in result if str(i["patient_id"]) == v]
    if v := request.args.get("site_id"):     result = [i for i in result if i["site_id"] == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"invoice_items": page_data, "meta": meta})

@app.route("/v1/payments")
def payments():
    result = list(g.data["payments"])
    if v := request.args.get("patient_id"):    result = [p for p in result if str(p["patient_id"]) == v]
    if v := request.args.get("site_id"):       result = [p for p in result if p["site_id"] == v]
    if v := request.args.get("dated_after"):   result = [p for p in result if p["dated_on"] >= v]
    if v := request.args.get("dated_before"):  result = [p for p in result if p["dated_on"] <= v]
    result = filter_updated_after(result)
    result.sort(key=lambda p: p["dated_on"])
    page_data, meta = paginate(result)
    total_value = sum(float(p["amount"]) for p in result)
    meta["total_payments_value"] = f"{total_value:.2f}"
    return jsonify({"payments": page_data, "meta": meta})

@app.route("/v1/payment_explanations")
def payment_explanations():
    result = list(g.data["payment_explanations"])
    if v := request.args.get("payment_id"): result = [e for e in result if str(e["payment_id"]) == v]
    page_data, meta = paginate(result)
    return jsonify({"payment_explanations": page_data, "meta": meta})

@app.route("/v1/payment_allocations")
def payment_allocations():
    result = list(g.data["payment_allocations"])
    if v := request.args.get("patient_id"):      result = [a for a in result if str(a["patient_id"]) == v]
    if v := request.args.get("invoice_item_id"): result = [a for a in result if a["invoice_item_id"] == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"payment_allocations": page_data, "meta": meta})


# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — TREATMENT PLANS
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/treatment_plans")
def treatment_plans():
    result = list(g.data["treatment_plans"])
    if v := request.args.get("patient_id"):     result = [t for t in result if str(t["patient_id"]) == v]
    if v := request.args.get("site_id"):        result = [t for t in result if t["site_id"] == v]
    if v := request.args.get("created_after"):  result = [t for t in result if t["created_at"][:10] >= v]
    if v := request.args.get("created_before"): result = [t for t in result if t["created_at"][:10] <= v]
    if v := request.args.get("status"):         result = [t for t in result if t["status"].lower() == v.lower()]
    result = filter_updated_after(result)
    result.sort(key=lambda t: t["created_at"])
    page_data, meta = paginate(result)
    return jsonify({"treatment_plans": page_data, "meta": meta})

@app.route("/v1/treatment_plan_items")
def treatment_plan_items():
    result = list(g.data["treatment_items"])
    if v := request.args.get("treatment_plan_id"): result = [i for i in result if str(i["treatment_plan_id"]) == v]
    if v := request.args.get("patient_id"):        result = [i for i in result if str(i["patient_id"]) == v]
    if v := request.args.get("site_id"):           result = [i for i in result if i["site_id"] == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"treatment_plan_items": page_data, "meta": meta})


# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — RECALLS
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/recalls")
def recalls():
    result = list(g.data["recalls"])
    if v := request.args.get("patient_id"):       result = [r for r in result if str(r["patient_id"]) == v]
    if v := request.args.get("site_id"):          result = [r for r in result if r["site_id"] == v]
    if v := request.args.get("practitioner_id"):  result = [r for r in result if str(r["practitioner_id"]) == v]
    if request.args.get("overdue") == "true":     result = [r for r in result if r["days_overdue"] > 0]
    result = filter_updated_after(result)
    result.sort(key=lambda r: r["due_date"])
    page_data, meta = paginate(result)
    return jsonify({"recalls": page_data, "meta": meta})


# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — NHS CLAIMS & PRACTITIONER DIARIES
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/nhs_claims")
def nhs_claims():
    result = list(g.data["nhs_claims"])
    if v := request.args.get("patient_id"):  result = [c for c in result if str(c["patient_id"]) == v]
    if v := request.args.get("contract_id"): result = [c for c in result if c["contract_id"] == v]
    if v := request.args.get("site_id"):     result = [c for c in result if c["site_id"] == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"nhs_claims": page_data, "meta": meta})

@app.route("/v1/practitioner_diary_entries")
def diary_entries():
    result = list(g.data["diary_entries"])
    if v := request.args.get("practitioner_id"): result = [d for d in result if str(d["practitioner_id"]) == v]
    if v := request.args.get("site_id"):         result = [d for d in result if d["site_id"] == v]
    if v := request.args.get("date_after"):      result = [d for d in result if d["date"] >= v]
    if v := request.args.get("date_before"):     result = [d for d in result if d["date"] <= v]
    result = filter_updated_after(result)
    result.sort(key=lambda d: d["start_time"])
    page_data, meta = paginate(result)
    return jsonify({"practitioner_diary_entries": page_data, "meta": meta})


# ══════════════════════════════════════════════════════════════════════════════
# ROOT — ENDPOINT INDEX
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/")
def index():
    return jsonify({
        "name": "Dentally Mock API",
        "version": "v1",
        "tenants": {
            "Smile Group (Oxford)":    f"Bearer {TENANT1_KEY}",
            "Bright Dental (Brighton)": f"Bearer {TENANT2_KEY}",
        },
        "endpoints": {
            "reference": [
                "GET /v1/practice",
                "GET /v1/sites",
                "GET /v1/users",
                "GET /v1/practitioners              ?site_id=",
                "GET /v1/payment_plans",
                "GET /v1/treatments",
                "GET /v1/treatment_categories",
                "GET /v1/acquisition_sources",
                "GET /v1/sundries                   ?site_id=",
                "GET /v1/contracts                  ?site_id=",
                "GET /v1/fees                       ?payment_plan_id=  &treatment_id=",
                "GET /v1/practitioner_diary_breaks  ?practitioner_diary_id=",
            ],
            "patients": [
                "GET /v1/patients                   ?site_id=  &active=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/patients/{id}",
                "GET /v1/accounts                   ?patient_id=  &page=  &per_page=",
                "GET /v1/patient_stats              ?patient_id=  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "appointments": [
                "GET /v1/appointments               ?site_id=  &practitioner_id=  &patient_id=  &state=  &after=YYYY-MM-DD  &before=YYYY-MM-DD  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/treatment_appointments     ?patient_id=  &treatment_plan_id=  &appointment_id=  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "invoices_and_payments": [
                "GET /v1/invoices                   ?site_id=  &patient_id=  &dated_after=  &dated_before=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/invoice_items              ?invoice_id=  &patient_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/payments                   ?site_id=  &patient_id=  &dated_after=  &dated_before=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/payment_explanations       ?payment_id=  &page=  &per_page=",
                "GET /v1/payment_allocations        ?patient_id=  &invoice_item_id=  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "treatment_plans": [
                "GET /v1/treatment_plans            ?site_id=  &patient_id=  &status=  &created_after=  &created_before=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/treatment_plan_items       ?treatment_plan_id=  &patient_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "recalls": [
                "GET /v1/recalls                    ?site_id=  &patient_id=  &practitioner_id=  &overdue=true  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "nhs": [
                "GET /v1/nhs_claims                 ?patient_id=  &contract_id=  &site_id=  &updated_after=ISO8601  &page=  &per_page=",
            ],
            "diaries": [
                "GET /v1/practitioner_diary_entries ?practitioner_id=  &site_id=  &date_after=  &date_before=  &updated_after=ISO8601  &page=  &per_page=",
                "GET /v1/practitioner_diary_breaks  ?practitioner_diary_id=  &page=  &per_page=",
            ],
        },
        "pagination": "All list endpoints support ?page= (default 1) and ?per_page= (default 25, max 100)",
        "note": "Test data only. Fixed random seeds — same data on every restart.",
    })


if __name__ == "__main__":
    print("Dentally Mock API  ->  http://localhost:5000")
    print("Endpoint index     ->  http://localhost:5000/\n")
    app.run(host="0.0.0.0", port=5000, debug=False)
