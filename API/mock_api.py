"""
Dentally Mock API
-----------------
Mimics the real Dentally REST API (https://api.dentally.co) with generated test data.
Matches real field names and JSON envelope structure so ETL code written against this
will work unchanged against the live API.

Usage:
    python mock_api.py
    API available at http://localhost:5000

Authentication:
    All endpoints (except GET /) require:
        Authorization: Bearer dev-mock-key-abc123
    Override the key via env var:
        DENTALLY_API_KEY=your-key python mock_api.py

Endpoints:
    GET /v1/sites
    GET /v1/users
    GET /v1/practitioners              ?site_id=
    GET /v1/payment_plans
    GET /v1/treatments
    GET /v1/patients                   ?site_id=  &updated_after=ISO8601  &page=  &per_page=
    GET /v1/patients/{id}
    GET /v1/accounts                   ?patient_id=  &page=  &per_page=
    GET /v1/appointments               ?site_id=  &practitioner_id=  &patient_id=
                                       &state=  &after=YYYY-MM-DD  &before=YYYY-MM-DD
                                       &updated_after=ISO8601  &page=  &per_page=
    GET /v1/invoices                   ?site_id=  &patient_id=
                                       &dated_after=  &dated_before=
                                       &updated_after=ISO8601  &page=  &per_page=
    GET /v1/invoice_items              ?invoice_id=  &patient_id=  &site_id=
                                       &updated_after=ISO8601  &page=  &per_page=
    GET /v1/payments                   ?patient_id=  &site_id=
                                       &dated_after=  &dated_before=
                                       &updated_after=ISO8601  &page=  &per_page=
    GET /v1/treatment_plans            ?patient_id=  &site_id=
                                       &created_after=  &created_before=
                                       &updated_after=ISO8601  &page=  &per_page=
    GET /v1/treatment_plan_items       ?treatment_plan_id=  &patient_id=  &site_id=
                                       &updated_after=ISO8601  &page=  &per_page=
    GET /v1/recalls                    ?patient_id=  &site_id=  &overdue=true
                                       &updated_after=ISO8601  &page=  &per_page=
    GET /v1/practitioner_diary_entries ?practitioner_id=  &site_id=
                                       &date_after=  &date_before=
                                       &updated_after=ISO8601  &page=  &per_page=
"""

import math
import os
import random
from datetime import date, datetime, timedelta

from flask import Flask, jsonify, request

app = Flask(__name__)
random.seed(42)  # Fixed seed — same data every restart

API_KEY = os.environ.get('DENTALLY_API_KEY', 'dev-mock-key-abc123')

@app.before_request
def check_api_key():
    if request.path == '/':
        return None
    if request.headers.get('Authorization') != f'Bearer {API_KEY}':
        return jsonify({'error': 'Unauthorized'}), 401

# ══════════════════════════════════════════════════════════════════════════════
# REFERENCE DATA
# ══════════════════════════════════════════════════════════════════════════════

SITES = [
    {
        "id": "site-hs-001",
        "name": "High Street",
        "address_line_1": "14 High Street",
        "town": "Oxford",
        "postcode": "OX1 4AA",
        "phone": "01865 123456",
        "email": "highstreet@smilegroup.co.uk",
    },
    {
        "id": "site-rv-002",
        "name": "Riverside",
        "address_line_1": "10 Riverside Walk",
        "town": "Oxford",
        "postcode": "OX2 6HH",
        "phone": "01865 234567",
        "email": "riverside@smilegroup.co.uk",
    },
    {
        "id": "site-ng-003",
        "name": "Northgate",
        "address_line_1": "45 Northgate",
        "town": "Oxford",
        "postcode": "OX3 9BB",
        "phone": "01865 345678",
        "email": "northgate@smilegroup.co.uk",
    },
]

USERS = [
    {"id": 1, "first_name": "Admin",   "last_name": "User",    "email": "admin@smilegroup.co.uk",   "role": "admin"},
    {"id": 2, "first_name": "Amir",    "last_name": "Ahmed",   "email": "a.ahmed@smilegroup.co.uk", "role": "dentist"},
    {"id": 3, "first_name": "Li",      "last_name": "Chen",    "email": "l.chen@smilegroup.co.uk",  "role": "dentist"},
    {"id": 4, "first_name": "Priya",   "last_name": "Patel",   "email": "p.patel@smilegroup.co.uk", "role": "dentist"},
    {"id": 5, "first_name": "Sarah",   "last_name": "Morris",  "email": "s.morris@smilegroup.co.uk","role": "hygienist"},
    {"id": 6, "first_name": "James",   "last_name": "Wright",  "email": "j.wright@smilegroup.co.uk","role": "dentist"},
    {"id": 7, "first_name": "Claire",  "last_name": "Booth",   "email": "c.booth@smilegroup.co.uk", "role": "receptionist"},
    {"id": 8, "first_name": "Marcus",  "last_name": "Hall",    "email": "m.hall@smilegroup.co.uk",  "role": "receptionist"},
]

PRACTITIONERS = [
    {"id": 2, "first_name": "Amir",  "last_name": "Ahmed",  "role": "dentist",   "site_id": "site-hs-001", "user_id": 2},
    {"id": 3, "first_name": "Li",    "last_name": "Chen",   "role": "dentist",   "site_id": "site-rv-002", "user_id": 3},
    {"id": 4, "first_name": "Priya", "last_name": "Patel",  "role": "dentist",   "site_id": "site-hs-001", "user_id": 4},
    {"id": 5, "first_name": "Sarah", "last_name": "Morris", "role": "hygienist", "site_id": "site-rv-002", "user_id": 5},
    {"id": 6, "first_name": "James", "last_name": "Wright", "role": "dentist",   "site_id": "site-ng-003", "user_id": 6},
]

PAYMENT_PLANS = [
    {"id": 1, "name": "NHS",           "nhs": True,  "monthly_charge": "0.00",  "dentist_recall_interval": 6,  "hygienist_recall_interval": 6,  "exam_duration": 20, "scale_polish_duration": 30},
    {"id": 2, "name": "Private",       "nhs": False, "monthly_charge": "0.00",  "dentist_recall_interval": 12, "hygienist_recall_interval": 6,  "exam_duration": 30, "scale_polish_duration": 45},
    {"id": 3, "name": "Care Plan",     "nhs": False, "monthly_charge": "14.99", "dentist_recall_interval": 9,  "hygienist_recall_interval": 6,  "exam_duration": 30, "scale_polish_duration": 45},
    {"id": 4, "name": "Premium Plan",  "nhs": False, "monthly_charge": "24.99", "dentist_recall_interval": 6,  "hygienist_recall_interval": 3,  "exam_duration": 45, "scale_polish_duration": 60},
]

TREATMENTS = [
    {"id": 1,  "name": "Examination",                  "code": "0101", "chart_type": "examination"},
    {"id": 2,  "name": "Scale and Polish",              "code": "0111", "chart_type": "hygiene"},
    {"id": 3,  "name": "X-Ray (bitewing)",              "code": "0201", "chart_type": "xray"},
    {"id": 4,  "name": "Filling (1 surface, composite)","code": "0301", "chart_type": "restorative"},
    {"id": 5,  "name": "Filling (2 surface, composite)","code": "0302", "chart_type": "restorative"},
    {"id": 6,  "name": "Filling (amalgam)",             "code": "0303", "chart_type": "restorative"},
    {"id": 7,  "name": "Extraction (simple)",           "code": "0401", "chart_type": "surgical"},
    {"id": 8,  "name": "Root Canal (anterior)",         "code": "0501", "chart_type": "endodontic"},
    {"id": 9,  "name": "Root Canal (molar)",            "code": "0502", "chart_type": "endodontic"},
    {"id": 10, "name": "Crown (porcelain fused metal)", "code": "0601", "chart_type": "prosthetic"},
    {"id": 11, "name": "Crown (full porcelain)",        "code": "0602", "chart_type": "prosthetic"},
    {"id": 12, "name": "Denture (full upper)",          "code": "0701", "chart_type": "prosthetic"},
    {"id": 13, "name": "Whitening (home kit)",          "code": "0801", "chart_type": "cosmetic"},
    {"id": 14, "name": "Whitening (in-chair)",          "code": "0802", "chart_type": "cosmetic"},
    {"id": 15, "name": "Implant Consultation",          "code": "0901", "chart_type": "implant"},
    {"id": 16, "name": "Implant Placement",             "code": "0902", "chart_type": "implant"},
    {"id": 17, "name": "Hygienist Treatment",           "code": "1001", "chart_type": "hygiene"},
    {"id": 18, "name": "Periodontal Treatment",         "code": "1002", "chart_type": "hygiene"},
    {"id": 19, "name": "Fissure Sealant",               "code": "0151", "chart_type": "preventive"},
    {"id": 20, "name": "Emergency Appointment",         "code": "9901", "chart_type": "emergency"},
]

# Private prices per treatment (NHS uses banded charges)
PRIVATE_PRICES = {
    1: (55, 85),    2: (70, 110),   3: (25, 45),    4: (120, 180),
    5: (150, 220),  6: (90, 140),   7: (180, 280),  8: (450, 650),
    9: (550, 850),  10: (650, 950), 11: (750, 1100),12: (1200, 1800),
    13: (280, 380), 14: (480, 680), 15: (150, 250), 16: (2000, 3500),
    17: (75, 120),  18: (120, 200), 19: (45, 75),   20: (85, 150),
}

NHS_BANDS = {1: 0.0, 2: 23.80, 3: 65.20}  # NHS England 2024 charges

# ══════════════════════════════════════════════════════════════════════════════
# DATA GENERATORS
# ══════════════════════════════════════════════════════════════════════════════

def _iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.000+00:00")

def _rand_date_offset(base, min_days, max_days):
    return base + timedelta(days=random.randint(min_days, max_days))


def gen_patients(n=180):
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

    patients = []
    for i in range(1, n + 1):
        fn = random.choice(first_names)
        ln = random.choice(last_names)
        dob = date(random.randint(1944, 2010), random.randint(1, 12), random.randint(1, 28))
        site = random.choice(SITES)
        pract = random.choice([p for p in PRACTITIONERS if p["role"] == "dentist"])
        hygienist = random.choice([p for p in PRACTITIONERS if p["role"] == "hygienist"])
        pp = random.choice(PAYMENT_PLANS)
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
            "town": "Oxford",
            "county": "Oxfordshire",
            "postcode": f"OX{random.randint(1, 4)} {random.randint(1, 9)}{random.choice('ABCDEFGHJKLMNPQRSTUVWXYZ')}{random.choice('ABCDEFGHJKLMNPQRSTUVWXYZ')}",
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


def gen_appointments(patients, n=1000):
    states = ["Arrived", "Completed", "Did Not Attend", "Cancelled", "Booked", "In Chair"]
    weights = [0.03, 0.68, 0.06, 0.08, 0.12, 0.03]
    reasons = [
        "Routine Examination", "Scale and Polish", "Filling", "Extraction",
        "Root Canal Treatment", "Crown Preparation", "Crown Fit", "Denture Review",
        "Hygiene Appointment", "Emergency - Pain", "Whitening Consultation",
        "Implant Consultation", "Post-Op Review", "New Patient Examination",
    ]

    appointments = []
    for i in range(1, n + 1):
        patient = random.choice(patients)
        pract = random.choice(PRACTITIONERS)
        apt_dt = datetime.now() - timedelta(days=random.randint(-90, 730))
        duration = random.choice([15, 20, 30, 40, 45, 60, 75, 90])
        state = random.choices(states, weights=weights)[0]
        if apt_dt > datetime.now():
            state = random.choice(["Booked", "Booked", "Booked", "Cancelled"])

        # Waiting / in-surgery times for completed appointments
        waiting_mins = random.randint(0, 20) if state == "Completed" else 0
        in_surgery_mins = duration + random.randint(-5, 10) if state == "Completed" else 0

        appointments.append({
            "id": i,
            "patient_id": patient["id"],
            "patient_name": f"{patient['first_name']} {patient['last_name']}",
            "practitioner_id": pract["id"],
            "site_id": patient["site_id"],
            "reason": random.choice(reasons),
            "start_time": _iso(apt_dt),
            "finish_time": _iso(apt_dt + timedelta(minutes=duration)),
            "duration": duration,
            "state": state,
            "did_not_attend": state == "Did Not Attend",
            "waiting_time": waiting_mins,
            "in_surgery_time": in_surgery_mins,
            "cancellation_reason": random.choice(["Patient request", "Practitioner unavailable", "Emergency", None]) if state == "Cancelled" else None,
            "notes": None,
            "created_at": _iso(apt_dt - timedelta(days=random.randint(1, 45))),
            "updated_at": _iso(apt_dt),
        })
    return appointments


def gen_invoices_and_items(appointments):
    invoices = []
    invoice_items = []
    inv_id = 1
    item_id = 1

    completed = [a for a in appointments if a["state"] == "Completed"]

    for apt in completed:
        patient = next(p for p in PATIENTS if p["id"] == apt["patient_id"])
        pp = next(p for p in PAYMENT_PLANS if p["id"] == patient["payment_plan_id"])
        is_nhs = pp["nhs"]
        apt_dt = datetime.fromisoformat(apt["start_time"].replace("+00:00", ""))

        n_items = random.randint(1, 3)
        chosen = random.sample(TREATMENTS, n_items)

        total = 0.0
        nhs_total = 0.0

        for t in chosen:
            if is_nhs:
                band = random.choices([1, 2, 3], weights=[0.25, 0.45, 0.30])[0]
                price = NHS_BANDS[band]
                nhs_charge = price
            else:
                lo, hi = PRIVATE_PRICES.get(t["id"], (50, 200))
                price = round(random.uniform(lo, hi), 2)
                nhs_charge = 0.0

            total += price
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


def gen_payments(invoices):
    methods = ["Cash", "Card", "Bank Transfer", "Direct Debit", "Cheque"]
    method_weights = [0.10, 0.65, 0.15, 0.08, 0.02]
    payments = []
    pay_id = 1

    for inv in invoices:
        if inv["paid"]:
            patient = next(p for p in PATIENTS if p["id"] == inv["patient_id"])
            pp = next(p for p in PAYMENT_PLANS if p["id"] == patient["payment_plan_id"])
            dated = datetime.fromisoformat(inv["dated_on"])

            payments.append({
                "id": pay_id,
                "account_id": inv["account_id"],
                "patient_id": inv["patient_id"],
                "site_id": inv["site_id"],
                "payment_plan_id": pp["id"],
                "practitioner_id": inv["user_id"],
                "user_id": inv["user_id"],
                "amount": inv["amount"],
                "amount_unexplained": "0.00",
                "dated_on": inv["paid_on"],
                "method": random.choices(methods, weights=method_weights)[0],
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


def gen_treatment_plans(patients, n=400):
    statuses = ["Draft", "Presented", "Accepted", "Partially Accepted", "Declined", "Completed"]
    weights  = [0.05,   0.12,        0.42,       0.15,                   0.08,       0.18]
    plans = []

    for i in range(1, n + 1):
        patient = random.choice(patients)
        pract = random.choice([p for p in PRACTITIONERS if p["role"] == "dentist"])
        created_at = datetime.now() - timedelta(days=random.randint(10, 730))
        status = random.choices(statuses, weights=weights)[0]
        is_nhs = random.random() > 0.55
        n_items = random.randint(1, 5)
        chosen = random.sample(TREATMENTS, n_items)

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


def gen_treatment_plan_items(treatment_plans):
    items = []
    item_id = 1

    for plan in treatment_plans:
        pract = next(p for p in PRACTITIONERS if p["id"] == plan["practitioner_id"])
        n_items = random.randint(1, 5)
        chosen = random.sample(TREATMENTS, n_items)
        created_at = datetime.fromisoformat(plan["created_at"].replace("+00:00", ""))

        for t in chosen:
            is_nhs = plan["nhs"]
            if is_nhs:
                price = NHS_BANDS[random.choice([1, 2, 3])]
            else:
                lo, hi = PRIVATE_PRICES.get(t["id"], (50, 200))
                price = round(random.uniform(lo, hi), 2)

            duration = random.choice([15, 20, 30, 45, 60])

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
                "duration": duration,
                "status": plan["status"],
                "created_at": _iso(created_at),
                "updated_at": _iso(created_at),
            })
            item_id += 1

    return items


def gen_recalls(patients):
    recalls = []
    recall_id = 1

    for p in patients:
        # Dentist recall
        recall_date = date.fromisoformat(p["dentist_recall_date"])
        overdue_days = (date.today() - recall_date).days
        recalls.append({
            "id": recall_id,
            "patient_id": p["id"],
            "patient_name": f"{p['first_name']} {p['last_name']}",
            "site_id": p["site_id"],
            "practitioner_id": p["dentist_id"],
            "recall_type": "dentist",
            "due_date": recall_date.isoformat(),
            "days_overdue": max(0, overdue_days),
            "times_contacted": random.randint(0, 4) if overdue_days > 0 else 0,
            "status": "Overdue" if overdue_days > 0 else "Due",
            "created_at": _iso(datetime.now() - timedelta(days=abs(overdue_days) + p["dentist_recall_interval"] * 30)),
            "updated_at": _iso(datetime.now() - timedelta(days=random.randint(0, 30))),
        })
        recall_id += 1

        # Hygienist recall
        recall_date = date.fromisoformat(p["hygienist_recall_date"])
        overdue_days = (date.today() - recall_date).days
        recalls.append({
            "id": recall_id,
            "patient_id": p["id"],
            "patient_name": f"{p['first_name']} {p['last_name']}",
            "site_id": p["site_id"],
            "practitioner_id": p["hygienist_id"],
            "recall_type": "hygienist",
            "due_date": recall_date.isoformat(),
            "days_overdue": max(0, overdue_days),
            "times_contacted": random.randint(0, 4) if overdue_days > 0 else 0,
            "status": "Overdue" if overdue_days > 0 else "Due",
            "created_at": _iso(datetime.now() - timedelta(days=abs(overdue_days) + p["hygienist_recall_interval"] * 30)),
            "updated_at": _iso(datetime.now() - timedelta(days=random.randint(0, 30))),
        })
        recall_id += 1

    return recalls


def gen_diary_entries(n_weeks=52):
    entries = []
    entry_id = 1
    start = date.today() - timedelta(weeks=n_weeks)

    for pract in PRACTITIONERS:
        current = start
        while current <= date.today():
            # Mon-Fri only
            if current.weekday() < 5:
                # Morning session
                session_start = datetime(current.year, current.month, current.day, 9, 0)
                duration = random.choice([120, 150, 180, 210, 240])
                break_count = random.randint(0, 2)
                break_mins = break_count * 15
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

                # Afternoon session (~70% of days)
                if random.random() > 0.3:
                    session_start = datetime(current.year, current.month, current.day, 13, 30)
                    duration = random.choice([120, 150, 180, 210])
                    break_count = random.randint(0, 1)
                    break_mins = break_count * 15
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


# ══════════════════════════════════════════════════════════════════════════════
# BUILD ALL DATA AT STARTUP
# ══════════════════════════════════════════════════════════════════════════════

print("Generating test data...")
PATIENTS         = gen_patients(180)
APPOINTMENTS     = gen_appointments(PATIENTS, 1000)
INVOICES, INVOICE_ITEMS = gen_invoices_and_items(APPOINTMENTS)
PAYMENTS         = gen_payments(INVOICES)
TREATMENT_PLANS  = gen_treatment_plans(PATIENTS, 400)
TREATMENT_ITEMS  = gen_treatment_plan_items(TREATMENT_PLANS)
RECALLS          = gen_recalls(PATIENTS)
DIARY_ENTRIES    = gen_diary_entries(52)

print(f"  Patients:             {len(PATIENTS)}")
print(f"  Appointments:         {len(APPOINTMENTS)}")
print(f"  Invoices:             {len(INVOICES)}")
print(f"  Invoice items:        {len(INVOICE_ITEMS)}")
print(f"  Payments:             {len(PAYMENTS)}")
print(f"  Treatment plans:      {len(TREATMENT_PLANS)}")
print(f"  Treatment plan items: {len(TREATMENT_ITEMS)}")
print(f"  Recalls:              {len(RECALLS)}")
print(f"  Diary entries:        {len(DIARY_ENTRIES)}")
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
        items[start : start + per_page],
        {"total": total, "current_page": page, "total_pages": math.ceil(total / per_page) if total else 0},
    )

def filter_updated_after(items):
    v = request.args.get('updated_after')
    if not v:
        return items
    return [i for i in items if i.get('updated_at', '') >= v]

def add_cors(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    return response

app.after_request(add_cors)

# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — REFERENCE DATA
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/sites")
def sites():
    return jsonify({"sites": SITES, "meta": {"total": len(SITES), "current_page": 1, "total_pages": 1}})

@app.route("/v1/users")
def users():
    page_data, meta = paginate(USERS)
    return jsonify({"users": page_data, "meta": meta})

@app.route("/v1/practitioners")
def practitioners():
    result = list(PRACTITIONERS)
    if sid := request.args.get("site_id"):
        result = [p for p in result if p["site_id"] == sid]
    page_data, meta = paginate(result)
    return jsonify({"practitioners": page_data, "meta": meta})

@app.route("/v1/payment_plans")
def payment_plans():
    return jsonify({"payment_plans": PAYMENT_PLANS, "meta": {"total": len(PAYMENT_PLANS), "current_page": 1, "total_pages": 1}})

@app.route("/v1/treatments")
def treatments():
    return jsonify({"treatments": TREATMENTS, "meta": {"total": len(TREATMENTS), "current_page": 1, "total_pages": 1}})

# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — PATIENTS & ACCOUNTS
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/patients")
def patients():
    result = list(PATIENTS)
    if sid := request.args.get("site_id"):
        result = [p for p in result if p["site_id"] == sid]
    if active := request.args.get("active"):
        result = [p for p in result if str(p["active"]).lower() == active.lower()]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"patients": page_data, "meta": meta})

@app.route("/v1/patients/<int:patient_id>")
def patient(patient_id):
    p = next((p for p in PATIENTS if p["id"] == patient_id), None)
    if not p:
        return jsonify({"error": "Patient not found"}), 404
    return jsonify({"patient": p})

@app.route("/v1/accounts")
def accounts():
    result = []
    for p in PATIENTS:
        inv = [i for i in INVOICES if i["patient_id"] == p["id"]]
        balance = sum(float(i["amount_outstanding"]) for i in inv)
        pp = next(x for x in PAYMENT_PLANS if x["id"] == p["payment_plan_id"])
        result.append({
            "id": p["account_id"],
            "patient_id": p["id"],
            "patient_name": f"{p['first_name']} {p['last_name']}",
            "current_balance": f"{-balance:.2f}",
            "opening_balance": "0.00",
            "planned_nhs_treatment_value": f"{round(random.uniform(0, 300), 2):.2f}" if pp["nhs"] else "0.00",
            "planned_private_treatment_value": f"{round(random.uniform(0, 1500), 2):.2f}" if not pp["nhs"] else "0.00",
        })
    if pid := request.args.get("patient_id"):
        result = [a for a in result if str(a["patient_id"]) == pid]
    page_data, meta = paginate(result)
    return jsonify({"accounts": page_data, "meta": meta})

# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — APPOINTMENTS
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/appointments")
def appointments():
    result = list(APPOINTMENTS)
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

# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — INVOICES & PAYMENTS
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/invoices")
def invoices():
    result = list(INVOICES)
    if v := request.args.get("patient_id"):    result = [i for i in result if str(i["patient_id"]) == v]
    if v := request.args.get("site_id"):       result = [i for i in result if i["site_id"] == v]
    if v := request.args.get("dated_after"):   result = [i for i in result if i["dated_on"] >= v]
    if v := request.args.get("dated_before"):  result = [i for i in result if i["dated_on"] <= v]
    result = filter_updated_after(result)
    result.sort(key=lambda i: i["dated_on"])
    page_data, meta = paginate(result)
    return jsonify({"invoices": page_data, "meta": meta})

@app.route("/v1/invoice_items")
def invoice_items():
    result = list(INVOICE_ITEMS)
    if v := request.args.get("invoice_id"):  result = [i for i in result if str(i["invoice_id"]) == v]
    if v := request.args.get("patient_id"): result = [i for i in result if str(i["patient_id"]) == v]
    if v := request.args.get("site_id"):    result = [i for i in result if i["site_id"] == v]
    result = filter_updated_after(result)
    page_data, meta = paginate(result)
    return jsonify({"invoice_items": page_data, "meta": meta})

@app.route("/v1/payments")
def payments():
    result = list(PAYMENTS)
    if v := request.args.get("patient_id"):   result = [p for p in result if str(p["patient_id"]) == v]
    if v := request.args.get("site_id"):      result = [p for p in result if p["site_id"] == v]
    if v := request.args.get("dated_after"):  result = [p for p in result if p["dated_on"] >= v]
    if v := request.args.get("dated_before"): result = [p for p in result if p["dated_on"] <= v]
    result = filter_updated_after(result)
    result.sort(key=lambda p: p["dated_on"])
    page_data, meta = paginate(result)
    total_value = sum(float(p["amount"]) for p in result)
    meta["total_payments_value"] = f"{total_value:.2f}"
    return jsonify({"payments": page_data, "meta": meta})

# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — TREATMENT PLANS
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/treatment_plans")
def treatment_plans():
    result = list(TREATMENT_PLANS)
    if v := request.args.get("patient_id"):      result = [t for t in result if str(t["patient_id"]) == v]
    if v := request.args.get("site_id"):         result = [t for t in result if t["site_id"] == v]
    if v := request.args.get("created_after"):   result = [t for t in result if t["created_at"][:10] >= v]
    if v := request.args.get("created_before"):  result = [t for t in result if t["created_at"][:10] <= v]
    if v := request.args.get("status"):          result = [t for t in result if t["status"].lower() == v.lower()]
    result = filter_updated_after(result)
    result.sort(key=lambda t: t["created_at"])
    page_data, meta = paginate(result)
    return jsonify({"treatment_plans": page_data, "meta": meta})

@app.route("/v1/treatment_plan_items")
def treatment_plan_items():
    result = list(TREATMENT_ITEMS)
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
    result = list(RECALLS)
    if v := request.args.get("patient_id"):      result = [r for r in result if str(r["patient_id"]) == v]
    if v := request.args.get("site_id"):         result = [r for r in result if r["site_id"] == v]
    if v := request.args.get("practitioner_id"): result = [r for r in result if str(r["practitioner_id"]) == v]
    if request.args.get("overdue") == "true":    result = [r for r in result if r["days_overdue"] > 0]
    result = filter_updated_after(result)
    result.sort(key=lambda r: r["due_date"])
    page_data, meta = paginate(result)
    return jsonify({"recalls": page_data, "meta": meta})

# ══════════════════════════════════════════════════════════════════════════════
# ROUTES — PRACTITIONER DIARIES
# ══════════════════════════════════════════════════════════════════════════════

@app.route("/v1/practitioner_diary_entries")
def diary_entries():
    result = list(DIARY_ENTRIES)
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
        "base_url": "http://localhost:5000/v1",
        "endpoints": {
            "reference": [
                "GET /v1/sites",
                "GET /v1/users",
                "GET /v1/practitioners         ?site_id=",
                "GET /v1/payment_plans",
                "GET /v1/treatments",
            ],
            "patients": [
                "GET /v1/patients              ?site_id=  &active=  &page=  &per_page=",
                "GET /v1/patients/{id}",
                "GET /v1/accounts              ?patient_id=  &page=  &per_page=",
            ],
            "appointments": [
                "GET /v1/appointments          ?site_id=  &practitioner_id=  &patient_id=  &state=  &after=YYYY-MM-DD  &before=YYYY-MM-DD  &page=  &per_page=",
            ],
            "invoices_and_payments": [
                "GET /v1/invoices              ?site_id=  &patient_id=  &dated_after=  &dated_before=  &page=  &per_page=",
                "GET /v1/invoice_items         ?invoice_id=  &patient_id=  &site_id=  &page=  &per_page=",
                "GET /v1/payments              ?site_id=  &patient_id=  &dated_after=  &dated_before=  &page=  &per_page=",
            ],
            "treatment_plans": [
                "GET /v1/treatment_plans       ?site_id=  &patient_id=  &status=  &created_after=  &created_before=  &page=  &per_page=",
                "GET /v1/treatment_plan_items  ?treatment_plan_id=  &patient_id=  &site_id=  &page=  &per_page=",
            ],
            "recalls": [
                "GET /v1/recalls               ?site_id=  &patient_id=  &practitioner_id=  &overdue=true  &page=  &per_page=",
            ],
            "diaries": [
                "GET /v1/practitioner_diary_entries  ?practitioner_id=  &site_id=  &date_after=  &date_before=  &page=  &per_page=",
            ],
        },
        "pagination": "All list endpoints support ?page= (default 1) and ?per_page= (default 25, max 100)",
        "note": "Test data only. Fixed random seed — same data on every restart.",
    })


if __name__ == "__main__":
    print("Dentally Mock API  ->  http://localhost:5000")
    print("Endpoint index     ->  http://localhost:5000/\n")
    app.run(host="0.0.0.0", port=5000, debug=False)
