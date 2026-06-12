"""
generate_data.py  —  rebuilt 2026-05-15; as-of date driven by GENERATE_AS_OF env var
Run:  python API/generate_data.py
      GENERATE_AS_OF=2026-07-01 python API/generate_data.py
"""
import json, os, random, uuid as _uuid
from datetime import date, datetime, timedelta
from pathlib import Path

random.seed(42)
TODAY   = date.fromisoformat(os.environ.get('GENERATE_AS_OF', '2026-07-01'))
START   = TODAY.replace(year=TODAY.year - 3)
FWD_END = TODAY + timedelta(days=428)  # ~14 months forward
NS      = _uuid.NAMESPACE_OID

def _u5(*p): return str(_uuid.uuid5(NS, "|".join(str(x) for x in p)))
def _iso(d, t="00:00:00"):
    if isinstance(d, datetime): return d.strftime("%Y-%m-%dT%H:%M:%S.000+00:00")
    return f"{d}T{t}.000+00:00"
def _fmt(v): return f"{float(v):.2f}"
def _add_months(d, m):
    mo=d.month-1+m; yr=d.year+mo//12; mo=mo%12+1
    dy=min(d.day,[31,29 if yr%4==0 and(yr%100!=0 or yr%400==0) else 28,
                  31,30,31,30,31,31,30,31,30,31][mo-1])
    return date(yr,mo,dy)

# Maps internal functional role names to values valid per the Dentally API constraint:
# Administrator, Dentist, Hygienist, Nurse, Practice Manager, Receptionist, Technician, Therapist
_API_ROLE = {
    "dentist":      "Dentist",
    "orthodontist": "Dentist",
    "specialist":   "Dentist",
    "hygienist":    "Hygienist",
    "tco":          "Receptionist",
}

BH = {
    date(2023,1,2),date(2023,4,7),date(2023,4,10),date(2023,5,1),
    date(2023,5,8),date(2023,5,29),date(2023,8,28),date(2023,12,25),date(2023,12,26),
    date(2024,1,1),date(2024,3,29),date(2024,4,1),date(2024,5,6),
    date(2024,5,27),date(2024,8,26),date(2024,12,25),date(2024,12,26),
    date(2025,1,1),date(2025,4,18),date(2025,4,21),date(2025,5,5),
    date(2025,5,26),date(2025,8,25),date(2025,12,25),date(2025,12,26),
    date(2026,1,1),date(2026,4,3),date(2026,4,6),date(2026,5,4),
    date(2026,5,25),date(2026,8,31),date(2026,12,25),date(2026,12,26),
}

# (code, desc, nhs_cat, uda_band, region, cat_name, priv_price, priv_dur)
_TX = [
    (101, "Examination",                    1,  1, "Full Mouth", "Examination & Assessment",   75,  30),
    (111, "Examination Extensive",           1,  1, "Full Mouth", "Examination & Assessment",  110,  45),
    (121, "Full Case Assessment",            1,  1, "Full Mouth", "Examination & Assessment",  150,  60),
    (201, "X-Ray Bitewing",                  1,  1, "Tooth",      "Examination & Assessment",   20,  10),
    (202, "X-Ray Periapical",                1,  1, "Tooth",      "Examination & Assessment",   20,  10),
    (204, "Panoramic (OPG)",                 1,  1, "Full Mouth", "Examination & Assessment",   85,  15),
    (601, "Oral Hygiene Instruction",        1,  1, "Full Mouth", "Preventive",                 40,  20),
    (711, "Fluoride Varnish",                1,  1, "Full Mouth", "Preventive",                 25,  10),
    (801, "Fissure Sealant",                 1,  1, "Tooth",      "Preventive",                 45,  15),
    (1001,"Scale & Polish",                  1,  1, "Gum",        "Periodontal",                75,  30),
    (1010,"Periodontal Treatment (Visit 1)", 2,  3, "Gum",        "Periodontal",               150,  45),
    (1011,"Periodontal Treatment (Visit 2)", 2,  3, "Gum",        "Periodontal",               150,  45),
    (1021,"Root Surface Debridement",        2,  3, "Gum",        "Periodontal",               220,  60),
    (1201,"Extraction (Simple)",             2,  3, "Jaw",        "Oral Surgery",              130,  20),
    (1202,"Extraction (Surgical)",           2,  3, "Jaw",        "Oral Surgery",              280,  45),
    (1301,"Root Canal (Anterior)",           2,  5, "Tooth",      "Endodontic",                450,  60),
    (1302,"Root Canal (Premolar)",           2,  5, "Tooth",      "Endodontic",                550,  75),
    (1303,"Root Canal (Molar)",              2,  7, "Tooth",      "Endodontic",                750,  90),
    (1401,"Amalgam Filling",                 2,  3, "Tooth",      "Restorative",               130,  30),
    (1421,"Composite Filling (1 surface)",   2,  3, "Tooth",      "Restorative",               150,  30),
    (1422,"Composite Filling (2 surface)",   2,  3, "Tooth",      "Restorative",               185,  40),
    (1423,"Composite Filling (3+ surfaces)", 2,  3, "Tooth",      "Restorative",               225,  50),
    (1601,"Crown (Porcelain Fused Metal)",   3, 12, "Tooth",      "Crowns & Bridges",          750,  60),
    (1602,"Crown (Full Ceramic)",            3, 12, "Tooth",      "Crowns & Bridges",          900,  60),
    (1611,"Bridge (per unit)",               3, 12, "Tooth",      "Crowns & Bridges",          850,  60),
    (1701,"Partial Denture",                 3, 12, "Arch",       "Prosthetic",               1200,  60),
    (1711,"Full Denture",                    3, 12, "Arch",       "Prosthetic",               1800,  60),
    (1721,"Inlay / Onlay",                   3, 12, "Tooth",      "Prosthetic",                550,  60),
    (1731,"Veneer",                          3, 12, "Tooth",      "Prosthetic",                650,  60),
    (2001,"Whitening (Home Kit)",          None, 0, "Full Mouth", "Cosmetic",                  300,  30),
    (2002,"Whitening (In-Chair)",          None, 0, "Full Mouth", "Cosmetic",                  550,  90),
    (2011,"Composite Bonding",             None, 0, "Tooth",      "Cosmetic",                  350,  60),
    (2101,"Implant Consultation",          None, 0, "Jaw",        "Implant",                   150,  45),
    (2102,"Implant Placement",             None, 0, "Jaw",        "Implant",                  1800,  90),
    (2103,"Implant Crown",                 None, 0, "Tooth",      "Implant",                  1200,  60),
    (9001,"Emergency Examination",           1,  1, "Full Mouth", "Emergency",                  75,  20),
    (9002,"Emergency Treatment",             2,  3, "Tooth",      "Emergency",                 200,  30),
]
_TX_ORTHO = [
    (8101,"Ortho Consultation",            None, 0, "Full Mouth", "Orthodontic",               150,  45),
    (8102,"Ortho Records",                 None, 0, "Full Mouth", "Orthodontic",               300,  30),
    (8111,"Fixed Appliance Fitting",       None, 0, "Full Mouth", "Orthodontic",               350,  60),
    (8112,"Adjustment",                    None, 0, "Full Mouth", "Orthodontic",                75,  30),
    (8113,"Debond",                        None, 0, "Full Mouth", "Orthodontic",               150,  45),
    (8114,"Retainer Fitting",              None, 0, "Full Mouth", "Orthodontic",               250,  45),
    (8115,"Retention Review",              None, 0, "Full Mouth", "Orthodontic",                75,  30),
    (8121,"Aligner Treatment",             None, 0, "Full Mouth", "Orthodontic",              3500,  60),
]
_TX_TCO = [
    (9101,"Treatment Consultation",        None, 0, "Full Mouth", "Non-clinical",                0,  30),
    (9102,"Smile Consultation",            None, 0, "Full Mouth", "Non-clinical",                0,  45),
]

_LAB   = {1601,1602,1611,1701,1711,1721,1731,2102,2103,8111,8121}
_BAND  = {1:27.90, 2:76.60, 3:332.10}
_PP_PRICE = {101:95, 111:145, 121:195}  # Premium Private exam price overrides
_PP_DUR   = {101:40, 111:60,  121:75}   # Premium Private exam duration overrides
_EXAM_CODES = {101, 111, 121}
_HYGIENE_CODE = 1001
_EMERGENCY_CODES = {9001, 9002}

# ─── TENANT DEFINITIONS ───────────────────────────────────────────────────────

def _contract(tid, site_id, site_code, year, target, uda_val, uoa_target=0, uoa_val=0,
              loc_id="", contract_number="", is_ortho=False):
    y0, y1 = year, year+1
    active = (y0 == 2026)
    suffix = "/O" if is_ortho else "/D"
    cn = contract_number or f"16C/{site_code}{suffix}/{y0-2022:02d}"
    return {
        "id": _u5("con", tid, site_id, y0, "ortho" if is_ortho else "dental"),
        "active": active,
        "contract_number": cn,
        "start_date": f"{y0}-04-01",
        "end_date":   f"{y1}-03-31",
        "name": f"{contract_number or cn} {y0}/{str(y1)[-2:]}",
        "nhs_location_id": loc_id,
        "nhs_site_id": site_code,
        "notes": None,
        "pds_plus": False,
        "site_id": site_id,
        "target": _fmt(target),
        "uda_value": _fmt(uda_val),
        "uoa_target": _fmt(uoa_target),
        "uoa_value": _fmt(uoa_val),
        "created_at": _iso(date(y0, 4, 1)),
        "updated_at": _iso(date(y0, 4, 1)),
    }

def _pp(id_, name, nhs=False, monthly="0.00", dr=12, hr=6, exam_dur=30, sp_dur=45, emg_dur=20,
        exam_sp_dur=None, patient_friendly=None, site_id=None, colour=None):
    return {
        "id": id_, "name": name, "nhs": nhs,
        "active": True,
        "monthly_charge": monthly,
        "dentist_recall_interval": dr, "hygienist_recall_interval": hr,
        "exam_duration": exam_dur,
        "scale_and_polish_duration": sp_dur,
        "emergency_duration": emg_dur,
        "exam_scale_and_polish_duration": exam_sp_dur,
        "patient_friendly_name": patient_friendly or name,
        "site_id": site_id,
        "colour": colour,
        "payment_plan_colour": None,
        "created_at": _iso(START),
    }

def _sundry(tid, site_id, name, price, nickname=None):
    return {
        "id": _u5("sun", tid, site_id, name),
        "name": name, "nickname": nickname or name[:8],
        "price": _fmt(price), "site_id": site_id,
    }

def _wl(tid, site_id, name, target_appt_days, target_treat_days=None):
    return {
        "id": _u5("wl", tid, site_id, name),
        "name": name, "active": True, "site_id": site_id,
        "default_appointment_reason": "New Patient Examination",
        "default_treatment_reason": None,
        "default_notes": None,
        "default_status": "waiting",
        "target_appointment_days": target_appt_days,
        "target_treatment_days": target_treat_days,
        "default_appointment_duration": 45,
        "default_treatment_duration": None,
    }

def _acq(id_, name, active=True):
    return {"id": id_, "name": name, "active": active, "notes": None}

def _cr(id_, reason, archived=False):
    return {
        "id": id_,
        "reason": reason,
        "reason_type": "cancellation",
        "archived": archived,
        "created_at": _iso(START),
        "updated_at": _iso(START),
    }

# ── T1 Smile Group ────────────────────────────────────────────────────────────
T1 = {
    "api_key": "dev-mock-key-abc123",
    "tenant_id": 1, "nhs": True, "has_ortho": True, "price_mult": 1.0, "n_patients": 300,
    "domain": "smilegroup.co.uk",
    "practice": {
        "id": _u5("practice",1), "name": "Smile Group", "nhs": True,
        "address_line_1": "14 High Street", "address_line_2": None,
        "town": "Oxford", "postcode": "OX1 4AA",
        "phone_number": "01865 123000", "email_address": "info@smilegroup.co.uk",
        "patient_email_address": "patients@smilegroup.co.uk",
        "website": "https://smilegroup.co.uk", "logo_url": "https://smilegroup.co.uk/logo.png",
        "slug": "smile-group", "time_zone": "Europe/London",
        "medical_history_expiry_days": 365,
        "custom_patient_field_label_1": None, "custom_patient_field_label_2": None,
        "oh_mon_open":"09:00","oh_mon_close":"17:30","oh_tues_open":"09:00","oh_tues_close":"17:30",
        "oh_wed_open":"09:00","oh_wed_close":"17:30","oh_thur_open":"09:00","oh_thur_close":"17:30",
        "oh_fri_open":"09:00","oh_fri_close":"17:30","oh_sat_open":None,"oh_sat_close":None,
        "oh_sun_open":None,"oh_sun_close":None,
    },
    "sites": [
        {"id":"site-hs","name":"High Street","active":True,"address_line_1":"14 High Street",
         "town":"Oxford","postcode":"OX1 4AA","phone_number":"01865 123456",
         "email_address":"highstreet@smilegroup.co.uk","nickname":"High St",
         "monday_open":"09:00","monday_close":"17:30","tuesday_open":"09:00","tuesday_close":"17:30",
         "wednesday_open":"09:00","wednesday_close":"17:30","thursday_open":"09:00","thursday_close":"17:30",
         "friday_open":"09:00","friday_close":"17:30","saturday_open":None,"saturday_close":None},
        {"id":"site-rv","name":"Riverside","active":True,"address_line_1":"10 Riverside Walk",
         "town":"Oxford","postcode":"OX2 6HH","phone_number":"01865 234567",
         "email_address":"riverside@smilegroup.co.uk","nickname":"Riverside",
         "monday_open":"09:00","monday_close":"17:30","tuesday_open":"09:00","tuesday_close":"17:30",
         "wednesday_open":"09:00","wednesday_close":"17:30","thursday_open":"09:00","thursday_close":"17:30",
         "friday_open":"09:00","friday_close":"17:30","saturday_open":None,"saturday_close":None},
        {"id":"site-ng","name":"Northgate","active":True,"address_line_1":"45 Northgate",
         "town":"Oxford","postcode":"OX3 9BB","phone_number":"01865 345678",
         "email_address":"northgate@smilegroup.co.uk","nickname":"Northgate",
         "monday_open":"09:00","monday_close":"17:30","tuesday_open":"09:00","tuesday_close":"17:30",
         "wednesday_open":"09:00","wednesday_close":"17:30","thursday_open":"09:00","thursday_close":"17:30",
         "friday_open":"09:00","friday_close":"17:30","saturday_open":None,"saturday_close":None},
    ],
    "payment_plans": [
        _pp(1,"NHS",nhs=True,dr=6,hr=6,exam_dur=20,sp_dur=30,emg_dur=20),
        _pp(2,"Private",dr=12,hr=6,exam_dur=30,sp_dur=45,emg_dur=20),
        _pp(3,"Care Plan",monthly="14.99",dr=12,hr=6,exam_dur=30,sp_dur=45,emg_dur=20),
        _pp(4,"Premium Private",monthly="29.99",dr=12,hr=3,exam_dur=40,sp_dur=45,emg_dur=20),
    ],
    "contracts": [
        # High Street dental
        _contract(1,"site-hs","FDX01",2023,1400,26.50,loc_id="QU9",contract_number="16C/FDX01/D"),
        _contract(1,"site-hs","FDX01",2024,1450,27.50,loc_id="QU9",contract_number="16C/FDX01/D"),
        _contract(1,"site-hs","FDX01",2025,1480,28.00,loc_id="QU9",contract_number="16C/FDX01/D"),
        _contract(1,"site-hs","FDX01",2026,1500,28.80,loc_id="QU9",contract_number="16C/FDX01/D"),
        # High Street ortho (Marcus Thompson UOA)
        _contract(1,"site-hs","FDX01",2023,0,0,uoa_target=280,uoa_val=80.00,loc_id="QU9",contract_number="16C/FDX01/O",is_ortho=True),
        _contract(1,"site-hs","FDX01",2024,0,0,uoa_target=300,uoa_val=82.00,loc_id="QU9",contract_number="16C/FDX01/O",is_ortho=True),
        _contract(1,"site-hs","FDX01",2025,0,0,uoa_target=315,uoa_val=84.00,loc_id="QU9",contract_number="16C/FDX01/O",is_ortho=True),
        _contract(1,"site-hs","FDX01",2026,0,0,uoa_target=315,uoa_val=86.00,loc_id="QU9",contract_number="16C/FDX01/O",is_ortho=True),
        # Riverside
        _contract(1,"site-rv","FDX02",2023,1800,26.00,loc_id="QU9",contract_number="16C/FDX02/D"),
        _contract(1,"site-rv","FDX02",2024,1750,27.00,loc_id="QU9",contract_number="16C/FDX02/D"),
        _contract(1,"site-rv","FDX02",2025,1730,27.80,loc_id="QU9",contract_number="16C/FDX02/D"),
        _contract(1,"site-rv","FDX02",2026,1725,28.50,loc_id="QU9",contract_number="16C/FDX02/D"),
        # Northgate
        _contract(1,"site-ng","FDX03",2023,2800,26.50,loc_id="QU9",contract_number="16C/FDX03/D"),
        _contract(1,"site-ng","FDX03",2024,2700,27.50,loc_id="QU9",contract_number="16C/FDX03/D"),
        _contract(1,"site-ng","FDX03",2025,2660,28.00,loc_id="QU9",contract_number="16C/FDX03/D"),
        _contract(1,"site-ng","FDX03",2026,2625,28.80,loc_id="QU9",contract_number="16C/FDX03/D"),
    ],
    "acquisition_sources": [
        _acq("acq-1-01","Online Marketing"),_acq("acq-1-02","Walk-in"),
        _acq("acq-1-03","Local Ad Campaign"),
    ],
    "cancellation_reasons": [
        _cr(1,"Patient cancelled - short notice"),_cr(2,"Patient cancelled - in advance"),
        _cr(3,"Patient DNA (did not attend)"),_cr(4,"Patient unwell"),
        _cr(5,"Practice cancelled - practitioner unwell"),_cr(6,"Practice cancelled - emergency"),
        _cr(7,"Work completed at previous visit"),_cr(8,"Treatment no longer required"),
        _cr(9,"Patient request"),_cr(10,"System error / admin"),
    ],
    "sundries": (
        [_sundry(1,"site-hs",n,p) for n,p in [
            ("Electric Toothbrush (Oral-B)",49.99),("Replacement Brush Heads (4-pack)",14.99),
            ("Whitening Toothpaste",7.99),("Interdental Brushes",4.99),
            ("Fluoride Mouthwash (500ml)",6.99),("Home Whitening Kit",149.00),("Retainer Cleaning Tablets",9.99)
        ]] +
        [_sundry(1,"site-rv",n,p) for n,p in [
            ("Electric Toothbrush (Oral-B)",49.99),("Replacement Brush Heads (4-pack)",14.99),
            ("Whitening Toothpaste",7.99),("Interdental Brushes",4.99),
            ("Fluoride Mouthwash (500ml)",6.99),("Home Whitening Kit",149.00),("Retainer Cleaning Tablets",9.99)
        ]] +
        [_sundry(1,"site-ng",n,p) for n,p in [
            ("Electric Toothbrush (Oral-B)",49.99),("Replacement Brush Heads (4-pack)",14.99),
            ("Whitening Toothpaste",7.99),("Interdental Brushes",4.99),
            ("Fluoride Mouthwash (500ml)",6.99),("Home Whitening Kit",149.00),("Retainer Cleaning Tablets",9.99)
        ]]
    ),
    "waiting_lists": [
        _wl(1,"site-hs","NHS New Patient",60),_wl(1,"site-hs","New Private Patient",30),
        _wl(1,"site-rv","NHS New Patient",45),
        _wl(1,"site-ng","NHS New Patient",30),_wl(1,"site-ng","New Private Patient",14),
    ],
    # Generation metadata (stripped from JSON output)
    "_prac_defs": [
        # id,fname,lname,title,role,site_id,gdc,nhs_pct,work_days,start,end,late_days,late_end,pp_ids,active
        {"id":1,"first_name":"Amir","last_name":"Hassan","title":"Dr","role":"dentist",
         "site_id":"site-hs","gdc_number":"123001","nhs_pct":0.20,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[1,3],"late_end":"19:30","pp_ids":[1,2,4],"performs_nhs":True,"active":True},
        {"id":2,"first_name":"Priya","last_name":"Sharma","title":"Dr","role":"dentist",
         "site_id":"site-hs","gdc_number":"123002","nhs_pct":0.0,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[2,4],"performs_nhs":False,"active":True},
        {"id":3,"first_name":"Li","last_name":"Chen","title":"Dr","role":"dentist",
         "site_id":"site-rv","gdc_number":"123003","nhs_pct":0.05,
         "work_days":[0,1,2,3],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2],"performs_nhs":True,"active":True},
        {"id":4,"first_name":"Fatima","last_name":"Al-Rashid","title":"Dr","role":"dentist",
         "site_id":"site-ng","gdc_number":"123004","nhs_pct":0.18,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2],"performs_nhs":True,"active":True},
        {"id":5,"first_name":"James","last_name":"Okonkwo","title":"Dr","role":"dentist",
         "site_id":"site-ng","gdc_number":"123005","nhs_pct":0.15,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2],"performs_nhs":True,"active":True},
        {"id":6,"first_name":"Oliver","last_name":"Bennett","title":"Dr","role":"dentist",
         "site_id":"site-hs","gdc_number":"123006","nhs_pct":0.20,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2,4],"performs_nhs":True,"active":True},
        {"id":7,"first_name":"Sarah","last_name":"Ng","title":"Ms","role":"orthodontist",
         "site_id":"site-hs","gdc_number":"123007","nhs_pct":0.0,
         "work_days":[0,1,2,3],"start_time":"09:00","end_time":"17:00",
         "late_days":[],"late_end":None,"pp_ids":[2],"performs_nhs":False,"active":True},
        {"id":8,"first_name":"Marcus","last_name":"Thompson","title":"Dr","role":"orthodontist",
         "site_id":"site-hs","gdc_number":"123008","nhs_pct":0.0,
         "work_days":[0,1,2,3],"start_time":"09:00","end_time":"17:00",
         "late_days":[],"late_end":None,"pp_ids":[2],"performs_nhs":False,"active":True,
         "has_uoa_contract":True},
        {"id":9,"first_name":"Rachel","last_name":"Patel","title":"Ms","role":"hygienist",
         "site_id":"site-hs","gdc_number":"123009","nhs_pct":0.15,
         "work_days":[0,2,4],"start_time":"09:00","end_time":"17:00",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":10,"first_name":"Sophie","last_name":"Carter","title":"Ms","role":"hygienist",
         "site_id":"site-rv","gdc_number":"123010","nhs_pct":0.10,
         "work_days":[1,3,4],"start_time":"09:00","end_time":"17:00",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":11,"first_name":"Yemi","last_name":"Adeyemi","title":"Ms","role":"hygienist",
         "site_id":"site-ng","gdc_number":"123011","nhs_pct":0.12,
         "work_days":[0,1,3],"start_time":"09:00","end_time":"17:00",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":12,"first_name":"Alex","last_name":"Stone","title":"Mr","role":"tco",
         "site_id":"site-hs","gdc_number":None,"nhs_pct":0.0,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[2,3,4],"performs_nhs":False,"active":True},
        {"id":13,"first_name":"Jordan","last_name":"Mills","title":"Ms","role":"tco",
         "site_id":"site-ng","gdc_number":None,"nhs_pct":0.0,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[2,3],"performs_nhs":False,"active":True},
    ],
    "_site_patient_split": {"site-hs":0.45,"site-rv":0.30,"site-ng":0.25},
}

# ── T2 Bright Dental ──────────────────────────────────────────────────────────
T2 = {
    "api_key": "dev-mock-key-tenant2",
    "tenant_id": 2, "nhs": False, "has_ortho": False, "price_mult": 1.25, "n_patients": 150,
    "domain": "brightdental.co.uk",
    "practice": {
        "id": _u5("practice",2), "name": "Bright Dental", "nhs": False,
        "address_line_1": "55 Kings Road", "address_line_2": None,
        "town": "Brighton", "postcode": "BN1 1AB",
        "phone_number": "01273 100000", "email_address": "info@brightdental.co.uk",
        "patient_email_address": "patients@brightdental.co.uk",
        "website": "https://brightdental.co.uk", "logo_url": "https://brightdental.co.uk/logo.png",
        "slug": "bright-dental", "time_zone": "Europe/London",
        "medical_history_expiry_days": 365,
        "custom_patient_field_label_1": None, "custom_patient_field_label_2": None,
        "oh_mon_open":"09:00","oh_mon_close":"17:30","oh_tues_open":"09:00","oh_tues_close":"17:30",
        "oh_wed_open":"09:00","oh_wed_close":"17:30","oh_thur_open":"09:00","oh_thur_close":"17:30",
        "oh_fri_open":"09:00","oh_fri_close":"17:30","oh_sat_open":"09:00","oh_sat_close":"13:00",
        "oh_sun_open":None,"oh_sun_close":None,
    },
    "sites": [
        {"id":"site-bd","name":"Bright Dental HQ","active":True,"address_line_1":"55 Kings Road",
         "town":"Brighton","postcode":"BN1 1AB","phone_number":"01273 100200",
         "email_address":"info@brightdental.co.uk","nickname":"Bright HQ",
         "monday_open":"09:00","monday_close":"17:30","tuesday_open":"09:00","tuesday_close":"17:30",
         "wednesday_open":"09:00","wednesday_close":"17:30","thursday_open":"09:00","thursday_close":"17:30",
         "friday_open":"09:00","friday_close":"17:30","saturday_open":"09:00","saturday_close":"13:00"},
    ],
    "payment_plans": [
        _pp(1,"Private",dr=12,hr=6,exam_dur=30,sp_dur=45,emg_dur=20),
        _pp(2,"Care Plan",monthly="17.99",dr=12,hr=6,exam_dur=30,sp_dur=45,emg_dur=20),
    ],
    "contracts": [],
    "acquisition_sources": [
        _acq("acq-2-01","Online Marketing"),_acq("acq-2-02","Walk-in"),
        _acq("acq-2-03","Local Ad Campaign"),
    ],
    "cancellation_reasons": [
        _cr(1,"Patient cancelled - short notice"),_cr(2,"Patient cancelled - in advance"),
        _cr(3,"Patient DNA"),_cr(4,"Practice cancelled - practitioner unwell"),
        _cr(5,"Treatment no longer required"),
    ],
    "sundries": [_sundry(2,"site-bd",n,p) for n,p in [
        ("Premium Electric Toothbrush",89.99),("Air Flosser",49.99),
        ("Premium Home Whitening Kit",199.00),("Fluoride Mouthwash (500ml)",8.99),
        ("Night Guard (stock)",39.99),("Whitening Toothpaste (premium)",12.99),
    ]],
    "waiting_lists": [],
    "_prac_defs": [
        {"id":1,"first_name":"Rahul","last_name":"Mehta","title":"Dr","role":"dentist",
         "site_id":"site-bd","gdc_number":"223001","nhs_pct":0.0,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[1,3],"late_end":"19:30","pp_ids":[1,2],"performs_nhs":False,"active":True},
        {"id":2,"first_name":"Emma","last_name":"Walsh","title":"Dr","role":"dentist",
         "site_id":"site-bd","gdc_number":"223002","nhs_pct":0.0,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2],"performs_nhs":False,"active":True},
        {"id":3,"first_name":"Sian","last_name":"Lloyd","title":"Dr","role":"dentist",
         "site_id":"site-bd","gdc_number":"223003","nhs_pct":0.0,
         "work_days":[0,2,3,4,5],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2],"performs_nhs":False,"active":True},
        {"id":4,"first_name":"Kavya","last_name":"Nair","title":"Dr","role":"specialist",
         "site_id":"site-bd","gdc_number":"223004","nhs_pct":0.0,
         "work_days":[0,1,2,3],"start_time":"09:00","end_time":"17:00",
         "late_days":[],"late_end":None,"pp_ids":[1],"performs_nhs":False,"active":True},
        {"id":5,"first_name":"Benjamin","last_name":"Foster","title":"Dr","role":"specialist",
         "site_id":"site-bd","gdc_number":"223005","nhs_pct":0.0,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2],"performs_nhs":False,"active":True},
        {"id":6,"first_name":"Laura","last_name":"Grant","title":"Ms","role":"hygienist",
         "site_id":"site-bd","gdc_number":"223006","nhs_pct":0.0,
         "work_days":[0,1,3,4],"start_time":"09:00","end_time":"17:00",
         "late_days":[],"late_end":None,"pp_ids":[1,2],"performs_nhs":False,"active":True},
        {"id":7,"first_name":"Nina","last_name":"Osei","title":"Ms","role":"hygienist",
         "site_id":"site-bd","gdc_number":"223007","nhs_pct":0.0,
         "work_days":[1,2,4,5],"start_time":"09:00","end_time":"17:00",
         "late_days":[],"late_end":None,"pp_ids":[1,2],"performs_nhs":False,"active":True},
        {"id":8,"first_name":"Charlotte","last_name":"Blake","title":"Ms","role":"tco",
         "site_id":"site-bd","gdc_number":None,"nhs_pct":0.0,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2],"performs_nhs":False,"active":True},
        {"id":9,"first_name":"Celine","last_name":"Dumont","title":"Ms","role":"tco",
         "site_id":"site-bd","gdc_number":None,"nhs_pct":0.0,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2],"performs_nhs":False,"active":True},
    ],
    "_site_patient_split": {"site-bd":1.0},
}

# ── T3 ClearSmile Manchester ──────────────────────────────────────────────────
T3 = {
    "api_key": "dev-mock-key-tenant3",
    "tenant_id": 3, "nhs": True, "has_ortho": False, "price_mult": 0.90, "n_patients": 120,
    "domain": "clearsmile-manchester.co.uk",
    "practice": {
        "id": _u5("practice",3), "name": "ClearSmile Manchester", "nhs": True,
        "address_line_1": "12 Oxford Road", "address_line_2": None,
        "town": "Manchester", "postcode": "M1 1AA",
        "phone_number": "0161 100000", "email_address": "info@clearsmile-manchester.co.uk",
        "patient_email_address": "patients@clearsmile-manchester.co.uk",
        "website": "https://clearsmile-manchester.co.uk", "logo_url": None,
        "slug": "clearsmile-manchester", "time_zone": "Europe/London",
        "medical_history_expiry_days": 365,
        "custom_patient_field_label_1": None, "custom_patient_field_label_2": None,
        "oh_mon_open":"09:00","oh_mon_close":"17:30","oh_tues_open":"09:00","oh_tues_close":"17:30",
        "oh_wed_open":"09:00","oh_wed_close":"17:30","oh_thur_open":"09:00","oh_thur_close":"17:30",
        "oh_fri_open":"09:00","oh_fri_close":"17:30","oh_sat_open":"09:00","oh_sat_close":"13:00",
        "oh_sun_open":None,"oh_sun_close":None,
    },
    "sites": [
        {"id":"site-ma","name":"Site A","active":True,"address_line_1":"12 Oxford Road",
         "town":"Manchester","postcode":"M1 1AA","phone_number":"0161 100100",
         "email_address":"sitea@clearsmile-manchester.co.uk","nickname":"Site A",
         "monday_open":"09:00","monday_close":"17:30","tuesday_open":"09:00","tuesday_close":"17:30",
         "wednesday_open":"09:00","wednesday_close":"17:30","thursday_open":"09:00","thursday_close":"17:30",
         "friday_open":"09:00","friday_close":"17:30","saturday_open":None,"saturday_close":None},
        {"id":"site-mb","name":"Site B","active":True,"address_line_1":"8 Deansgate",
         "town":"Manchester","postcode":"M2 2BB","phone_number":"0161 200200",
         "email_address":"siteb@clearsmile-manchester.co.uk","nickname":"Site B",
         "monday_open":"09:00","monday_close":"17:30","tuesday_open":"09:00","tuesday_close":"17:30",
         "wednesday_open":"09:00","wednesday_close":"17:30","thursday_open":"09:00","thursday_close":"17:30",
         "friday_open":"09:00","friday_close":"17:30","saturday_open":"09:00","saturday_close":"13:00"},
    ],
    "payment_plans": [
        _pp(1,"NHS",nhs=True,dr=6,hr=6,exam_dur=20,sp_dur=30,emg_dur=20),
        _pp(2,"Private",dr=12,hr=6,exam_dur=30,sp_dur=45,emg_dur=20),
        _pp(3,"Care Plan",monthly="12.99",dr=12,hr=6,exam_dur=30,sp_dur=45,emg_dur=20),
    ],
    "contracts": [
        _contract(3,"site-ma","FMC01",2023,1200,26.00,loc_id="QOP",contract_number="16C/FMC01/D"),
        _contract(3,"site-ma","FMC01",2024,1180,27.00,loc_id="QOP",contract_number="16C/FMC01/D"),
        _contract(3,"site-ma","FMC01",2025,1150,27.80,loc_id="QOP",contract_number="16C/FMC01/D"),
        _contract(3,"site-ma","FMC01",2026,1125,28.50,loc_id="QOP",contract_number="16C/FMC01/D"),
        _contract(3,"site-mb","FMC02",2023,1250,26.00,loc_id="QOP",contract_number="16C/FMC02/D"),
        _contract(3,"site-mb","FMC02",2024,1280,27.00,loc_id="QOP",contract_number="16C/FMC02/D"),
        _contract(3,"site-mb","FMC02",2025,1320,27.80,loc_id="QOP",contract_number="16C/FMC02/D"),
        _contract(3,"site-mb","FMC02",2026,1350,28.50,loc_id="QOP",contract_number="16C/FMC02/D"),
    ],
    "acquisition_sources": [
        _acq("acq-3-01","Online Marketing"),_acq("acq-3-02","Walk-in"),
        _acq("acq-3-03","Local Ad Campaign"),
    ],
    "cancellation_reasons": [
        _cr(1,"Patient cancelled - short notice"),_cr(2,"Patient cancelled - in advance"),
        _cr(3,"Patient DNA"),_cr(4,"Patient unwell"),
        _cr(5,"Practice cancelled - practitioner unwell"),_cr(6,"Treatment no longer required"),
    ],
    "sundries": [_sundry(3,"site-ma",n,p) for n,p in [
        ("Electric Toothbrush",44.99),("Interdental Brushes",4.99),
        ("Mouthwash (500ml)",5.99),("Home Whitening Kit",129.00),("Whitening Toothpaste",6.99),
    ]] + [_sundry(3,"site-mb",n,p) for n,p in [
        ("Electric Toothbrush",44.99),("Interdental Brushes",4.99),
        ("Mouthwash (500ml)",5.99),("Home Whitening Kit",129.00),("Whitening Toothpaste",6.99),
    ]],
    "waiting_lists": [
        _wl(3,"site-ma","NHS New Patient",60),
        _wl(3,"site-mb","NHS New Patient",30),
    ],
    "_prac_defs": [
        {"id":1,"first_name":"Amara","last_name":"Obi","title":"Dr","role":"dentist",
         "site_id":"site-ma","gdc_number":"323001","nhs_pct":0.15,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":2,"first_name":"David","last_name":"Park","title":"Dr","role":"dentist",
         "site_id":"site-mb","gdc_number":"323002","nhs_pct":0.25,
         "work_days":[0,1,2,3,4,5],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":3,"first_name":"Mei","last_name":"Zhang","title":"Dr","role":"dentist",
         "site_id":"site-ma","gdc_number":"323003","nhs_pct":0.20,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":4,"first_name":"Hannah","last_name":"Reed","title":"Ms","role":"hygienist",
         "site_id":"site-ma","gdc_number":"323004","nhs_pct":0.15,
         "work_days":[0,2,4],"start_time":"09:00","end_time":"17:00",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":5,"first_name":"Tom","last_name":"Walsh","title":"Mr","role":"tco",
         "site_id":"site-mb","gdc_number":None,"nhs_pct":0.0,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[2,3],"performs_nhs":False,"active":True},
    ],
    "_site_patient_split": {"site-ma":0.55,"site-mb":0.45},
}

# ── T4 ClearSmile Birmingham ──────────────────────────────────────────────────
T4 = {
    "api_key": "dev-mock-key-tenant4",
    "tenant_id": 4, "nhs": True, "has_ortho": False, "price_mult": 0.90, "n_patients": 120,
    "domain": "clearsmile-birmingham.co.uk",
    "practice": {
        "id": _u5("practice",4), "name": "ClearSmile Birmingham", "nhs": True,
        "address_line_1": "22 New Street", "address_line_2": None,
        "town": "Birmingham", "postcode": "B1 1AA",
        "phone_number": "0121 100000", "email_address": "info@clearsmile-birmingham.co.uk",
        "patient_email_address": "patients@clearsmile-birmingham.co.uk",
        "website": "https://clearsmile-birmingham.co.uk", "logo_url": None,
        "slug": "clearsmile-birmingham", "time_zone": "Europe/London",
        "medical_history_expiry_days": 365,
        "custom_patient_field_label_1": None, "custom_patient_field_label_2": None,
        "oh_mon_open":"09:00","oh_mon_close":"17:30","oh_tues_open":"09:00","oh_tues_close":"17:30",
        "oh_wed_open":"09:00","oh_wed_close":"17:30","oh_thur_open":"09:00","oh_thur_close":"17:30",
        "oh_fri_open":"09:00","oh_fri_close":"17:30","oh_sat_open":None,"oh_sat_close":None,
        "oh_sun_open":None,"oh_sun_close":None,
    },
    "sites": [
        {"id":"site-bm","name":"Main","active":True,"address_line_1":"22 New Street",
         "town":"Birmingham","postcode":"B1 1AA","phone_number":"0121 100100",
         "email_address":"info@clearsmile-birmingham.co.uk","nickname":"Main",
         "monday_open":"09:00","monday_close":"17:30","tuesday_open":"09:00","tuesday_close":"17:30",
         "wednesday_open":"09:00","wednesday_close":"17:30","thursday_open":"09:00","thursday_close":"17:30",
         "friday_open":"09:00","friday_close":"17:30","saturday_open":None,"saturday_close":None},
    ],
    "payment_plans": [
        _pp(1,"NHS",nhs=True,dr=6,hr=6,exam_dur=20,sp_dur=30,emg_dur=20),
        _pp(2,"Private",dr=12,hr=6,exam_dur=30,sp_dur=45,emg_dur=20),
        _pp(3,"Care Plan",monthly="12.99",dr=12,hr=6,exam_dur=30,sp_dur=45,emg_dur=20),
    ],
    "contracts": [
        _contract(4,"site-bm","FBM01",2023,2150,26.20,loc_id="QHL",contract_number="16C/FBM01/D"),
        _contract(4,"site-bm","FBM01",2024,2180,27.20,loc_id="QHL",contract_number="16C/FBM01/D"),
        _contract(4,"site-bm","FBM01",2025,2220,28.00,loc_id="QHL",contract_number="16C/FBM01/D"),
        _contract(4,"site-bm","FBM01",2026,2250,28.80,loc_id="QHL",contract_number="16C/FBM01/D"),
    ],
    "acquisition_sources": [
        _acq("acq-4-01","Online Marketing"),_acq("acq-4-02","Walk-in"),
        _acq("acq-4-03","Local Ad Campaign"),
    ],
    "cancellation_reasons": [
        _cr(1,"Patient cancelled - short notice"),_cr(2,"Patient cancelled - in advance"),
        _cr(3,"Patient DNA"),_cr(4,"Patient unwell"),
        _cr(5,"Practice cancelled - practitioner unwell"),
    ],
    "sundries": [_sundry(4,"site-bm",n,p) for n,p in [
        ("Electric Toothbrush",39.99),("Interdental Brushes",4.49),
        ("Mouthwash (500ml)",5.49),("Fluoride Toothpaste",5.99),
    ]],
    "waiting_lists": [_wl(4,"site-bm","NHS New Patient",45)],
    "_prac_defs": [
        {"id":1,"first_name":"Kieran","last_name":"Murphy","title":"Dr","role":"dentist",
         "site_id":"site-bm","gdc_number":"423001","nhs_pct":0.22,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":2,"first_name":"Chloe","last_name":"Davies","title":"Dr","role":"dentist",
         "site_id":"site-bm","gdc_number":"423002","nhs_pct":0.20,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":3,"first_name":"Rhys","last_name":"Edwards","title":"Dr","role":"dentist",
         "site_id":"site-bm","gdc_number":"423003","nhs_pct":0.18,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":4,"first_name":"Gemma","last_name":"Fox","title":"Ms","role":"hygienist",
         "site_id":"site-bm","gdc_number":"423004","nhs_pct":0.12,
         "work_days":[0,2,4],"start_time":"09:00","end_time":"17:00",
         "late_days":[],"late_end":None,"pp_ids":[1,2,3],"performs_nhs":True,"active":True},
        {"id":5,"first_name":"Daniel","last_name":"Hughes","title":"Mr","role":"tco",
         "site_id":"site-bm","gdc_number":None,"nhs_pct":0.0,
         "work_days":[0,1,2,3,4],"start_time":"09:00","end_time":"17:30",
         "late_days":[],"late_end":None,"pp_ids":[2,3],"performs_nhs":False,"active":True},
    ],
    "_site_patient_split": {"site-bm":1.0},
}

TENANT_DEFS = [T1, T2, T3, T4]

# ─── NAME POOLS ───────────────────────────────────────────────────────────────
_FM = ["James","Oliver","Harry","George","Noah","Jack","Charlie","Alfie","Ethan","William",
       "Muhammad","Ali","Ahmed","Liam","Henry","Edward","Thomas","Daniel","Samuel","Joseph"]
_FF = ["Olivia","Amelia","Isla","Ava","Emily","Isabella","Mia","Sophia","Grace","Lily",
       "Fatima","Aisha","Zara","Sophie","Charlotte","Emma","Poppy","Chloe","Lucy","Hannah"]
_LN = ["Smith","Jones","Williams","Brown","Taylor","Davies","Wilson","Evans","Thomas","Roberts",
       "Johnson","White","Martin","Thompson","Garcia","Robinson","Clark","Lewis","Walker","Hall",
       "Patel","Shah","Khan","Ahmed","Ali","Hassan","Singh","Kumar","Sharma","Gupta","Obi","Park"]
_ST = ["High Street","Church Lane","Victoria Road","Mill Lane","Park Avenue","Station Road",
       "The Green","Queen Street","Oak Drive","Grove Lane","Manor Road","Castle Street"]
_ET = [1,1,1,1,1,3,3,8,9,10,12,13,15,16,99]  # Ethnicity distribution

# ─── TREATMENT & CATEGORY GENERATION ─────────────────────────────────────────

def gen_treatments(tdef, tx_list):
    tid = tdef["tenant_id"]
    nhs_tenant = tdef["nhs"]
    cats = gen_treatment_categories(tdef)
    cat_map = {c["name"]: c["id"] for c in cats}
    out = []
    for i, row in enumerate(tx_list, 1):
        code, desc, nhs_cat, uda, region, cat_name, _, _ = row
        code_str = f"{code:04d}" if code < 10000 else str(code)
        out.append({
            "id": i,
            "code": code_str,
            "nomenclature": desc,
            "patient_nomenclature": desc,
            "description": desc,
            "active": True,
            "nhs_treatment_cat": nhs_cat if nhs_tenant else None,
            "uda_band": uda if nhs_tenant else 0,
            "region": region,
            "treatment_category_id": cat_map.get(cat_name, 1),
            "notes": None,
            "patient_description": None,
            "created_at": _iso(START),
            "updated_at": _iso(START),
        })
    return out

def gen_treatment_categories(tdef):
    tid = tdef["tenant_id"]
    if tdef["nhs"]:
        names = ["Examination & Assessment","Preventive","Periodontal","Restorative",
                 "Endodontic","Oral Surgery","Prosthetic","Cosmetic","Implant","Emergency","Non-clinical"]
        if tdef.get("has_ortho"):
            names.insert(7, "Orthodontic")
    else:
        names = ["Consultation & Assessment","Preventive & Hygiene","Periodontal","Restorative",
                 "Endodontic","Oral Surgery","Prosthetic","Cosmetic & Aesthetic","Implant","Emergency","Non-clinical"]
    return [{"id":i,"name":n,"tenant_id":tid} for i,n in enumerate(names,1)]

def gen_fees(tdef, treatments, payment_plans):
    tid = tdef["tenant_id"]
    mult = tdef["price_mult"]
    pp_by_id = {pp["id"]: pp for pp in payment_plans}
    tx_map = {}
    tx_list_raw = _TX + (_TX_ORTHO if tdef.get("has_ortho") else []) + _TX_TCO
    for row in tx_list_raw:
        code, _, _, _, _, _, priv_price, priv_dur = row
        tx_map[code] = (priv_price, priv_dur)

    out = []
    for tx in treatments:
        code = int(tx["code"])
        priv_price, priv_dur = tx_map.get(code, (0, 30))
        for pp in payment_plans:
            pp_id = pp["id"]
            pp_name = pp["name"]
            if pp_name == "NHS":
                price = 0.0; dur = priv_dur
            elif pp_name == "Care Plan":
                price = 0.0 if code in {101,111,1001} else round(priv_price * mult, 2)
                dur = priv_dur
            elif pp_name == "Premium Private":
                price = _PP_PRICE[code] if code in _PP_PRICE else round(priv_price * 1.25, 2)
                dur = _PP_DUR.get(code, priv_dur)
            else:  # Private
                price = round(priv_price * mult, 2)
                dur = priv_dur
            out.append({
                "id": _u5("fee", tid, pp_id, tx["id"]),
                "payment_plan_id": pp_id,
                "treatment_id": tx["id"],
                "multiple_pricing": code in {1421,1422,1423},
                "price_one": _fmt(price),
                "price_two": None,
                "price_three": None,
                "price_four": None,
                "price_five": None,
                "duration_one": dur,
                "duration_two": None,
                "duration_three": None,
                "duration_four": None,
                "duration_five": None,
            })
    return out

# ─── USERS & PRACTITIONERS ────────────────────────────────────────────────────

def gen_users_and_practitioners(tdef):
    tid = tdef["tenant_id"]
    domain = tdef["domain"]
    prac_defs = tdef["_prac_defs"]
    contracts_by_site = {}
    for c in tdef.get("contracts", []):
        if c.get("active") and not c.get("uoa_target","0") != "0":
            contracts_by_site.setdefault(c["site_id"], c)
    # Active 2026-27 dental contracts per site
    dental_contracts = {c["site_id"]: c for c in tdef.get("contracts",[])
                        if c.get("active") and float(c.get("target","0")) > 0}
    uoa_contracts = {c["site_id"]: c for c in tdef.get("contracts",[])
                     if c.get("active") and float(c.get("uoa_target","0")) > 0}

    users = [{"id":0,"first_name":"Admin","last_name":"User",
               "title":"Mr","middle_name":None,
               "email":f"admin@{domain}","role":"admin","active":True,
               "mobile_phone":None,"site_id":None,
               "created_at":_iso(START),"updated_at":_iso(START),
               "last_login":_iso(START)}]
    practitioners = []

    for p in prac_defs:
        uid = p["id"]
        fn, ln = p["first_name"], p["last_name"]
        email = f"{fn[0].lower()}.{ln.lower().replace(' ','').replace('-','')}@{domain}"
        mobile = f"07{(uid * 137 + tid * 31) % 900000000:09d}"[:12]
        users.append({
            "id": uid, "first_name": fn, "last_name": ln,
            "title": p["title"], "middle_name": None,
            "email": email, "role": _API_ROLE.get(p["role"], p["role"]), "active": p["active"],
            "mobile_phone": mobile,
            "site_id": p["site_id"],
            "permission_level": 1,
            "image_url": None,
            "created_at": _iso(START), "updated_at": _iso(START),
            "last_login": _iso(START),
        })
        # contract_targets
        cts = None
        contract_targets = []
        if p["performs_nhs"] and p["role"] in ("dentist","orthodontist"):
            site = p["site_id"]
            if p.get("has_uoa_contract") and site in uoa_contracts:
                c = uoa_contracts[site]
                contract_targets = [{"id":1,"contract_id":c["id"],
                                     "uda_target":0,"uoa_target":int(float(c["uoa_target"])),"default":True}]
            elif site in dental_contracts:
                c = dental_contracts[site]
                contract_targets = [{"id":1,"contract_id":c["id"],
                                     "uda_target":int(float(c["target"])),"uoa_target":0,"default":True}]
        cts = json.dumps(contract_targets) if contract_targets else None

        # Default contract for this site
        default_contract_id = None
        if p["site_id"] in dental_contracts:
            default_contract_id = dental_contracts[p["site_id"]]["id"]
        elif p["site_id"] in uoa_contracts:
            default_contract_id = uoa_contracts[p["site_id"]]["id"]

        pcat = ("dentist" if p["role"] in ("dentist","orthodontist","specialist")
                else "hygienist" if p["role"] == "hygienist" else "dental_nurse")
        # Colour palette: cycle through a set of hex colours
        _colours = ["#4A90D9","#E67E22","#27AE60","#8E44AD","#E74C3C",
                    "#16A085","#2980B9","#F39C12","#1ABC9C","#D35400",
                    "#C0392B","#7D3C98","#117A65"]
        colour = _colours[(uid - 1) % len(_colours)]

        # nhs_number: same as gdc_number for simplicity (real API returns separate field)
        nhs_number = p.get("gdc_number")

        user_obj = {
            "id": uid,
            "first_name": fn,
            "last_name": ln,
            "role": _API_ROLE.get(p["role"], p["role"]),
            "title": p["title"],
            "email": email,
            "mobile_phone": mobile,
            "middle_name": None,
            "permission_level": 1,
            "image_url": None,
            "created_at": _iso(START),
            "updated_at": _iso(START),
            "last_login": _iso(START),
        }

        practitioners.append({
            "id": uid, "user_id": uid,
            "site_id": p["site_id"], "active": p["active"],
            "gdc_number": p.get("gdc_number"),
            "nhs_number": nhs_number,
            "default_contract_id": default_contract_id,
            "colour": colour,
            "contract_targets": contract_targets,
            "contract_targets_string": cts,
            "performs_nhs": p["performs_nhs"],
            "practitioner_category": pcat,
            "user_first_name":     fn,
            "user_last_name":      ln,
            "user_role":           _API_ROLE.get(p["role"], p["role"]),
            "user_title":          p["title"],
            "user_email":          email,
            "user_mobile_phone":   mobile,
            "user_middle_name":    None,
            "user_permission_level": 1,
            "user_image_url":      None,
            "user_created_at":     _iso(START),
            "user_updated_at":     _iso(START),
            "user_last_login":     _iso(START),
        })
    return users, practitioners

# ─── DIARY ────────────────────────────────────────────────────────────────────

def gen_diary(tdef, prac_defs):
    tid = tdef["tenant_id"]
    entries, breaks = [], []
    diary_id_seq = [0]

    def _next_id():
        diary_id_seq[0] += 1
        return diary_id_seq[0]

    for p in prac_defs:
        pid = p["id"]
        work_days = set(p["work_days"])
        late_days = set(p.get("late_days", []))
        start_t = p.get("start_time", "09:00")
        end_t = p.get("end_time", "17:30")
        late_end = p.get("late_end", "17:30") or end_t

        # Generate ~20 absence days per year across 4 holiday blocks
        rng_h = random.Random(tid * 1000 + pid)
        absence_dates = set()
        d = START
        while d <= FWD_END:
            year = d.year
            blocks = [
                (date(year,1,2), date(year,2,14), 5),
                (date(year,4,1), date(year,5,31), 5),
                (date(year,7,1), date(year,8,31), 7),
                (date(year,10,1), date(year,11,30), 3),
            ]
            for bstart, bend, n in blocks:
                if bstart < START: bstart = START
                if bend > FWD_END: bend = FWD_END
                candidates = [bstart + timedelta(k) for k in range((bend-bstart).days+1)
                              if (bstart+timedelta(k)).weekday() in work_days]
                for ad in rng_h.sample(candidates, min(n, len(candidates))):
                    absence_dates.add(ad)
            d = date(year+1,1,1)

        cur = START
        while cur <= FWD_END:
            if cur.weekday() in work_days and cur not in BH and cur not in absence_dates:
                is_late = cur.weekday() in late_days
                et = late_end if is_late else end_t
                eid = _u5("diary", tid, pid, str(cur))
                entries.append({
                    "id": eid,
                    "practitioner_id": pid,
                    "site_id": p["site_id"],
                    "date": str(cur),
                    "start_time": _iso(cur, start_t),
                    "end_time": _iso(cur, et),
                    "created_at": _iso(cur),
                    "updated_at": _iso(cur),
                })
                # Lunch break for all
                breaks.append({
                    "id": _u5("brk", tid, pid, str(cur)),
                    "practitioner_diary_id": eid,
                    "name": "Lunch",
                    "start_time": _iso(cur, "13:00"),
                    "end_time": _iso(cur, "14:00"),
                })
            cur += timedelta(1)
    return entries, breaks

# ─── ROOMS ────────────────────────────────────────────────────────────────────

def gen_rooms(tdef):
    tid = tdef["tenant_id"]
    practice_id = tdef["practice"]["id"]
    # Surgery counts per site based on tenant/site size
    _site_surgery_counts = {
        "site-hs": 3, "site-rv": 2, "site-ng": 3,
        "site-bd": 2,
        "site-ma": 2, "site-mb": 2,
        "site-bm": 2,
    }
    _colours = ["#4A90D9","#E67E22","#27AE60","#8E44AD","#E74C3C","#16A085","#2980B9","#F39C12"]
    rooms = []
    room_id_seq = 0
    for site in tdef["sites"]:
        site_id = site["id"]
        n_surgeries = _site_surgery_counts.get(site_id, 2)
        for n in range(1, n_surgeries + 1):
            room_id_seq += 1
            rooms.append({
                "id": _u5("room", tid, site_id, n),
                "name": f"Surgery {n}",
                "site_id": site_id,
                "practice_id": practice_id,
                "colour": _colours[(room_id_seq - 1) % len(_colours)],
                "calendar_position": n,
                "created_at": _iso(START),
                "updated_at": _iso(START),
            })
    return rooms


# ─── PATIENTS ─────────────────────────────────────────────────────────────────

def gen_patients(tdef, rng):
    tid = tdef["tenant_id"]
    n = tdef["n_patients"]
    split = tdef["_site_patient_split"]
    prac_defs = tdef["_prac_defs"]
    acq_ids = [a["id"] for a in tdef["acquisition_sources"]]
    params = tdef.get("_params", {})
    active_rate = params.get("active_rate", 0.95)
    new_patient_rate = params.get("new_patient_rate", 0.0)  # fraction of patients who joined after START
    email_rate = params.get("email_rate", 1.0)
    phone_rate = params.get("phone_rate", 0.92)
    # Build site → dentist list and site → hygienist list
    site_dentists = {}
    site_hygienists = {}
    for p in prac_defs:
        if p["role"] in ("dentist","orthodontist","specialist"):
            site_dentists.setdefault(p["site_id"], []).append(p)
        elif p["role"] == "hygienist":
            site_hygienists.setdefault(p["site_id"], []).append(p)

    pp_by_id = {pp["id"]: pp for pp in tdef["payment_plans"]}
    nhs_pp_id = next((pp["id"] for pp in tdef["payment_plans"] if pp.get("nhs")), None)

    patients = []
    for i in range(1, n+1):
        # Assign site
        r = rng.random()
        cum = 0.0
        site_id = list(split.keys())[0]
        for sid, frac in split.items():
            cum += frac
            if r < cum:
                site_id = sid
                break

        # Assign dentist
        dentists = site_dentists.get(site_id, [])
        if not dentists:
            dentists = [p for p in prac_defs if p["role"]=="dentist"]
        dentist = rng.choice(dentists)

        # Assign hygienist (~75% of adults)
        hyg_list = site_hygienists.get(site_id, [])

        # Payment plan: nhs_pct chance of NHS, else pick from dentist's private pp_ids
        use_nhs = nhs_pp_id and rng.random() < dentist["nhs_pct"]
        if use_nhs:
            pp_id = nhs_pp_id
        else:
            private_pps = [pid for pid in dentist["pp_ids"] if pid != nhs_pp_id]
            pp_id = rng.choice(private_pps) if private_pps else dentist["pp_ids"][0]

        # Demographics
        is_female = rng.random() < 0.52
        first = rng.choice(_FF if is_female else _FM)
        last = rng.choice(_LN)
        # Age: 10% under 18, 80% 18-70, 10% 70+
        r_age = rng.random()
        if r_age < 0.10:
            age = rng.randint(3, 17)
        elif r_age < 0.90:
            age = rng.randint(18, 70)
        else:
            age = rng.randint(70, 90)
        dob = TODAY - timedelta(days=age*365 + rng.randint(0,364))

        hygienist_id = (rng.choice([p["id"] for p in hyg_list])
                        if hyg_list and age >= 18 and rng.random() < 0.75
                        else None)

        # NHS exemption (~15% of NHS patients)
        exemption = None
        if use_nhs and rng.random() < 0.15:
            if age < 18:
                exemption = "A"
            else:
                exemption = rng.choice(["D","E","C","H"])

        # Acquisition source (weighted: Google + word of mouth most common)
        acq_weights = [3 if "Google" in a else 2 if "Word" in a or "Walk" in a else 1 for a in acq_ids]
        acq_id = rng.choices(acq_ids, weights=acq_weights, k=1)[0]

        # Address
        house_num = rng.randint(1, 150)
        street = rng.choice(_ST)
        town_map = {"site-hs":"Oxford","site-rv":"Oxford","site-ng":"Oxford",
                    "site-bd":"Brighton","site-ma":"Manchester","site-mb":"Manchester","site-bm":"Birmingham"}
        town = town_map.get(site_id, "London")
        postcode_map = {"site-hs":"OX1","site-rv":"OX2","site-ng":"OX3","site-bd":"BN1",
                        "site-ma":"M1","site-mb":"M2","site-bm":"B1"}
        pc_area = postcode_map.get(site_id, "SW1")
        postcode = f"{pc_area} {rng.randint(1,9)}{rng.choice('ABCDEFGH')}{rng.choice('ABCDEFGHJKLMNPQRSTUVWXY')}"

        # Created date: legacy patients joined before START; new patients (new_patient_rate)
        # joined during the data window so their first exam falls within it
        if new_patient_rate > 0 and rng.random() < new_patient_rate:
            max_days = max(1, (TODAY - START - timedelta(days=90)).days)
            created = START + timedelta(days=rng.randint(1, max_days))
        else:
            created_offset = rng.randint(0, 365*5)
            created = START - timedelta(days=created_offset)

        # Ethnicity
        ethnicity = rng.choice(_ET)

        is_female_bool = is_female
        title_female = rng.choice(["Mrs","Ms","Miss"])
        title_male   = rng.choice(["Mr","Mr","Mr","Dr"])
        pat_title = title_female if is_female_bool else title_male

        recall_methods = ["sms","sms","sms","email","email","letter"]
        recall_method = rng.choice(recall_methods)

        use_email = rng.random() > 0.1
        use_sms   = rng.random() > 0.15
        preferred_phone = rng.choice(["mobile","mobile","mobile","home","work"])

        # preferred_name: ~15% chance
        preferred_name = first if rng.random() < 0.15 else None

        # work_phone: ~30% chance
        work_phone = (f"0{rng.randint(1000,9999)} {rng.randint(100000,999999)}"
                      if rng.random() < 0.30 else None)

        # emergency contact: ~60% chance
        if rng.random() < 0.60:
            ec_rel = rng.choice(["Spouse","Partner","Parent","Sibling","Friend","Child"])
            ec_name = f"{rng.choice(_FF if rng.random()<0.5 else _FM)} {last}"
            ec_phone = f"07{rng.randint(100,999)} {rng.randint(100000,999999)}"
        else:
            ec_rel = None; ec_name = None; ec_phone = None

        # archived_reason: only for inactive patients
        is_active = rng.random() < active_rate
        archived_reason = rng.choice(["Moved away","Deceased","No longer a patient",None]) if not is_active else None

        # medical alert: ~5% chance
        has_alert = rng.random() < 0.05
        alert_texts = ["Penicillin allergy","Latex allergy","Warfarin","Diabetes","Hypertension","Asthma"]

        pp_def = pp_by_id.get(pp_id, {})

        patients.append({
            "id": i,
            "title": pat_title,
            "first_name": first,
            "preferred_name": preferred_name,
            "middle_name": None,
            "last_name": last,
            "date_of_birth": str(dob),
            "gender": "Female" if is_female else "Male",
            "email_address": f"{first.lower()}.{last.lower()}{i}@example.com" if rng.random() < email_rate else None,
            "mobile_phone": f"07{rng.randint(100,999)} {rng.randint(100000,999999)}" if rng.random() < phone_rate else None,
            "home_phone": f"0{rng.randint(1000,9999)} {rng.randint(100000,999999)}" if rng.random() < 0.20 else None,
            "work_phone": work_phone,
            "address_line_1": f"{house_num} {street}",
            "address_line_2": None,
            "town": town,
            "county": None,
            "postcode": postcode,
            "site_id": site_id,
            "dentist_id": dentist["id"],
            "hygienist_id": hygienist_id,
            "payment_plan_id": pp_id,
            "account_id": i,
            "active": is_active,
            "nhs_exemption_code": exemption,
            "nhs_number": f"NHS{rng.randint(100000000,999999999)}" if use_nhs else None,
            "ni_number": f"{rng.choice('ABCEGHJKLMNOPRSTWXYZ')}{rng.choice('ABCEGHJKLMNPRSTWXYZ')}{rng.randint(100000,999999)}{rng.choice('ABCD')}" if age >= 16 else None,
            "ethnicity_id": ethnicity,
            "acquisition_source_id": acq_id,
            "recall_method": recall_method,
            "dentist_recall_interval": pp_def.get("dentist_recall_interval", 6),
            "hygienist_recall_interval": pp_def.get("hygienist_recall_interval", 6),
            "marketing": rng.random() < 0.70,
            "medical_alert": has_alert,
            "medical_alert_text": rng.choice(alert_texts) if has_alert else None,
            "occupation": None,
            "use_email": use_email,
            "use_sms": use_sms,
            "preferred_phone_number": preferred_phone,
            "emergency_contact_name": ec_name,
            "emergency_contact_relationship": ec_rel,
            "emergency_contact_phone": ec_phone,
            "archived_reason": archived_reason,
            "legacy_id": None,
            "created_at": _iso(created),
            "updated_at": _iso(created),
        })
    return patients

# ─── APPOINTMENTS ─────────────────────────────────────────────────────────────

def gen_appointments(tdef, patients, diary_set, prac_defs_by_id, tx_by_code, rooms, rng):
    """diary_set: set of (prac_id, date_str) for valid working days."""
    tid = tdef["tenant_id"]
    rooms_by_site = {}
    for r in rooms:
        rooms_by_site.setdefault(r["site_id"], []).append(r["id"])
    nhs_pp_id = next((pp["id"] for pp in tdef["payment_plans"] if pp.get("nhs")), None)
    care_plan_pp_id = next((pp["id"] for pp in tdef["payment_plans"] if pp["name"]=="Care Plan"), None)
    cr_ids = [c["id"] for c in tdef["cancellation_reasons"]]
    pp_by_id = {pp["id"]: pp for pp in tdef["payment_plans"]}
    params = tdef.get("_params", {})
    dna_rate              = params.get("dna_rate", 0.05)
    cancel_rate           = params.get("cancel_rate", 0.03)
    treatment_followup_rate = params.get("treatment_followup_rate", 0.35)
    max_tx_followups      = params.get("max_tx_followups", 1)
    bbyl_rate_tx          = params.get("bbyl_rate_tx", 0.35)
    hygiene_rate_nhs      = params.get("hygiene_rate_nhs", 0.8)
    hygiene_rate_private  = params.get("hygiene_rate_private", 0.4)
    bbyl_rate_hyg         = params.get("bbyl_rate_hyg", 0.40)
    recall_booking_rate   = params.get("recall_booking_rate", 0.35)

    appointments = []
    apt_id = 0

    # Build per-practitioner available dates
    prac_dates = {}
    for (pid, dstr) in diary_set:
        prac_dates.setdefault(pid, []).append(dstr)
    for pid in prac_dates:
        prac_dates[pid].sort()

    # Hygienist IDs by site
    site_hygienists = {}
    for p in tdef["_prac_defs"]:
        if p["role"] == "hygienist":
            site_hygienists.setdefault(p["site_id"], []).append(p["id"])

    # Slot tracker: prac_id → {date_str: count} (O(1) per lookup)
    used_slots = {}

    def _book_slot(pid, dates_list, after_date=None, before_date=None):
        """Find an unused date for practitioner pid."""
        for _ in range(50):
            if not dates_list:
                return None
            dstr = rng.choice(dates_list)
            d = date.fromisoformat(dstr)
            if after_date and d < after_date:
                continue
            if before_date and d > before_date:
                continue
            key = (pid, dstr)
            used = used_slots.setdefault(pid, {})
            count = used.get(dstr, 0)
            if count < 20:
                used[dstr] = count + 1
                return d
        return None

    def _slot_times(d, slot_n, dur_min):
        # Slots start at 09:00, each 30 min
        start_min = 9*60 + slot_n*30
        end_min = start_min + dur_min
        return (f"{start_min//60:02d}:{start_min%60:02d}:00",
                f"{end_min//60:02d}:{end_min%60:02d}:00")

    for pat in patients:
        pid = pat["dentist_id"]
        pp_id = pat["payment_plan_id"]
        site_id = pat["site_id"]
        is_nhs = (pp_id == nhs_pp_id)
        is_care = (pp_id == care_plan_pp_id)
        pat_id = pat["id"]

        if pid not in prac_dates:
            continue
        pdates = prac_dates[pid]

        # Scheduling anchor: new patients (created_at > START) start from their join date
        pat_created_str = pat.get("created_at", "")[:10]
        try:
            pat_start = max(START, date.fromisoformat(pat_created_str))
        except ValueError:
            pat_start = START
        recall_months = 6 if is_nhs else 12
        months_in_practice = max(recall_months, (TODAY - pat_start).days // 30)
        n_exams = (months_in_practice // recall_months) + rng.randint(0, 1)
        n_exams = min(n_exams, (36 // recall_months) + 2)  # cap at ~3.5 years

        # Spread exams across START..TODAY
        exam_codes_used = []
        prev_exam_date = None

        for exam_num in range(n_exams):
            # Target date — new patients use pat_start as anchor; legacy use even distribution
            if pat_start > START:
                target = pat_start + timedelta(days=int(exam_num * recall_months * 30))
            else:
                target = START + timedelta(days=int(exam_num * (36 / n_exams) * 30.5))
            if target >= TODAY:
                # Future exam
                target = TODAY + timedelta(days=rng.randint(7, 180))
                if target > FWD_END:
                    break
                d = _book_slot(pid, pdates, after_date=TODAY)
            else:
                d = _book_slot(pid, pdates, after_date=target - timedelta(30),
                               before_date=target + timedelta(30))
            if d is None:
                continue

            # First ever appointment = extensive exam (0111), subsequent = routine (0101)
            is_first = (prev_exam_date is None and exam_num == 0)
            exam_code = 111 if is_first else 101
            tx = tx_by_code.get(exam_code)
            tx_id = tx["id"] if tx else None
            pp_exam_dur = pp_by_id.get(pp_id, {}).get("exam_dur", 20)
            dur = pp_exam_dur if is_first else max(10, pp_exam_dur - 5)

            is_past = d < TODAY
            if is_past:
                r = rng.random()
                if r < dna_rate:                    state = "did_not_attend"
                elif r < dna_rate + cancel_rate:    state = "cancelled"
                else:                               state = "completed"
            else:
                state = "booked"

            cancel_id = rng.choice(cr_ids) if state in ("cancelled","did_not_attend") else None
            slot_n = used_slots.get(pid, {})
            start_t, end_t = _slot_times(d, rng.randint(0,14), dur)
            apt_id += 1
            appointments.append({
                "id": apt_id,
                "patient_id": pat_id,
                "practitioner_id": pid,
                "user_id": pid,
                "payment_plan_id": pp_id,
                "room_id": rng.choice(rooms_by_site.get(site_id, [None])),
                "start_time": _iso(d, start_t),
                "finish_time": _iso(d, end_t),
                "duration": dur,
                "state": state,
                "reason": "New Patient Examination" if is_first else "Routine Examination",
                "treatment_id": tx_id,
                "appointment_cancellation_reason_id": cancel_id,
                "online_booking": False,
                "booked_via_api": False,
                "arrived_at": _iso(d, start_t) if state == "completed" else None,
                "completed_at": _iso(d, end_t) if state == "completed" else None,
                "cancelled_at": _iso(d) if state == "cancelled" else None,
                "did_not_attend_at": _iso(d) if state == "did_not_attend" else None,
                "uuid": _u5("apt", tid, apt_id),
                "patient_name": None,
                "patient_image_url": None,
                "notes": None,
                "treatment_description": None,
                "confirmed_at": None,
                "in_surgery_at": _iso(d, start_t) if state == "completed" else None,
            })

            if state == "completed":
                prev_exam_date = d
                # Treatment follow-ups: loop max_tx_followups times; each is independent
                tx_last_date = d
                for _tx_i in range(max_tx_followups):
                    if rng.random() < treatment_followup_rate and is_past:
                        # ~12% chance is a Review-type appointment
                        if rng.random() < 0.12:
                            tx_code = rng.choice([2001, 2002, 2011, 2101, 9101, 9102])
                        else:
                            tx_code = rng.choice([1401, 1421, 1201, 201, 801, 1301])
                        ttx = tx_by_code.get(tx_code)
                        tdur = 30
                        td = _book_slot(pid, pdates,
                                        after_date=tx_last_date + timedelta(3),
                                        before_date=tx_last_date + timedelta(42))
                        if td:
                            ts_t, te_t = _slot_times(td, rng.randint(0,14), tdur)
                            tx_state  = "completed" if td < TODAY else "booked"
                            tx_bbyl   = rng.random() < bbyl_rate_tx
                            tx_online = (not tx_bbyl) and rng.random() < 0.20
                            apt_id += 1
                            appointments.append({
                                "id": apt_id,
                                "patient_id": pat_id,
                                "practitioner_id": pid,
                                "user_id": pid,
                                "payment_plan_id": pp_id,
                                "room_id": rng.choice(rooms_by_site.get(site_id, [None])),
                                "start_time": _iso(td, ts_t),
                                "finish_time": _iso(td, te_t),
                                "duration": tdur,
                                "state": tx_state,
                                "reason": ttx["description"] if ttx else "Treatment",
                                "treatment_id": ttx["id"] if ttx else None,
                                "appointment_cancellation_reason_id": None,
                                "online_booking": tx_online,
                                "booked_via_api": tx_bbyl or tx_online,
                                "pending_at": _iso(tx_last_date) if tx_bbyl else None,
                                "arrived_at": _iso(td, ts_t) if tx_state == "completed" else None,
                                "completed_at": _iso(td, te_t) if tx_state == "completed" else None,
                                "cancelled_at": None,
                                "did_not_attend_at": None,
                                "uuid": _u5("apt", tid, apt_id),
                                "patient_name": None,
                                "patient_image_url": None,
                                "notes": None,
                                "treatment_description": None,
                                "confirmed_at": None,
                                "in_surgery_at": _iso(td, ts_t) if tx_state == "completed" else None,
                            })
                            tx_last_date = td

                # Hygiene appointment (every 6 months for care plan / NHS, annually for private)
                hyg_pids = site_hygienists.get(site_id, [])
                hyg_chance = hygiene_rate_nhs if (is_nhs or is_care) else hygiene_rate_private
                if hyg_pids and rng.random() < hyg_chance:
                    hpid = rng.choice(hyg_pids)
                    if hpid in prac_dates:
                        hd = _book_slot(hpid, prac_dates[hpid],
                                        after_date=d + timedelta(14),
                                        before_date=d + timedelta(90))
                        if hd:
                            hs_t, he_t = _slot_times(hd, rng.randint(0,14), 30)
                            htx = tx_by_code.get(1001)
                            hyg_state  = "completed" if hd < TODAY else "booked"
                            hyg_bbyl   = rng.random() < bbyl_rate_hyg
                            hyg_online = (not hyg_bbyl) and rng.random() < 0.25
                            apt_id += 1
                            appointments.append({
                                "id": apt_id,
                                "patient_id": pat_id,
                                "practitioner_id": hpid,
                                "user_id": hpid,
                                "payment_plan_id": pp_id,
                                "room_id": rng.choice(rooms_by_site.get(prac_defs_by_id[hpid]["site_id"], [None])),
                                "start_time": _iso(hd, hs_t),
                                "finish_time": _iso(hd, he_t),
                                "duration": 30,
                                "state": hyg_state,
                                "reason": "Scale & Polish",
                                "treatment_id": htx["id"] if htx else None,
                                "appointment_cancellation_reason_id": None,
                                "online_booking": hyg_online,
                                "booked_via_api": hyg_bbyl or hyg_online,
                                "pending_at": _iso(d) if hyg_bbyl else None,
                                "arrived_at": _iso(hd, hs_t) if hyg_state == "completed" else None,
                                "completed_at": _iso(hd, he_t) if hyg_state == "completed" else None,
                                "cancelled_at": None,
                                "did_not_attend_at": None,
                                "uuid": _u5("apt", tid, apt_id),
                                "patient_name": None,
                                "patient_image_url": None,
                                "notes": None,
                                "treatment_description": None,
                                "confirmed_at": None,
                                "in_surgery_at": _iso(hd, hs_t) if hyg_state == "completed" else None,
                            })

        # recall_booking_rate of patients who have had exams get a future booked recall appointment.
        # Simulates patients who have already scheduled their next recall visit.
        if prev_exam_date is not None and rng.random() < recall_booking_rate:
            due_date = prev_exam_date + timedelta(days=recall_months * 30)
            after_d  = max(TODAY, due_date - timedelta(14))
            before_d = FWD_END
            fd = _book_slot(pid, pdates, after_date=after_d, before_date=before_d)
            if fd is not None and fd >= TODAY:
                fs_t, fe_t = _slot_times(fd, rng.randint(0, 14), 20)
                booked_on   = tx_last_date
                rc_online   = rng.random() < 0.35
                rc_bbyl     = (not rc_online) and rng.random() < bbyl_rate_tx
                apt_id    += 1
                appointments.append({
                    "id":                     apt_id,
                    "patient_id":             pat_id,
                    "practitioner_id":        pid,
                    "user_id":                pid,
                    "payment_plan_id":        pp_id,
                    "room_id":                rng.choice(rooms_by_site.get(site_id, [None])),
                    "start_time":             _iso(fd, fs_t),
                    "finish_time":            _iso(fd, fe_t),
                    "duration":               20,
                    "state":                  "booked",
                    "reason":                 "Recall Examination",
                    "treatment_id":           None,
                    "appointment_cancellation_reason_id": None,
                    "online_booking":         rc_online,
                    "booked_via_api":         rc_bbyl or rc_online,
                    "pending_at":             _iso(booked_on) if rc_bbyl else None,
                    "arrived_at":             None,
                    "completed_at":           None,
                    "cancelled_at":           None,
                    "did_not_attend_at":      None,
                    "uuid":                   _u5("apt", tid, apt_id),
                    "patient_name":           None,
                    "patient_image_url":      None,
                    "notes":                  None,
                    "treatment_description":  None,
                    "confirmed_at":           None,
                    "in_surgery_at":          None,
                })

    return appointments

# ─── TREATMENT PLANS & ITEMS ──────────────────────────────────────────────────

def gen_treatment_plans_and_items(tdef, patients, appointments, tx_by_id, fee_map, rng):
    """fee_map: {(pp_id, tx_id): price_float}"""
    tid = tdef["tenant_id"]
    nhs_pp_id = next((pp["id"] for pp in tdef["payment_plans"] if pp.get("nhs")), None)
    pat_pp = {p["id"]: p["payment_plan_id"] for p in patients}
    plan_acceptance_rate = tdef.get("_params", {}).get("plan_acceptance_rate", 1.0)

    # Practitioners available as referrers (dentists/orthodontists/specialists only)
    all_prac_ids = [p["id"] for p in tdef["_prac_defs"]
                    if p["role"] in ("dentist", "orthodontist", "specialist")]

    # Band UDA values
    uda_for_band = {1:1.0, 2:3.0, 3:5.0, 4:7.0, 5:12.0}
    band_uda = {1:1, 2:3, 3:5, 5:5, 7:7, 12:12}  # nhs_cat→uda mapping

    # Group completed past appointments by patient
    pat_apts = {}
    for a in appointments:
        if a["state"] == "completed" and a["start_time"][:10] < str(TODAY):
            pat_apts.setdefault(a["patient_id"], []).append(a)
    for pid in pat_apts:
        pat_apts[pid].sort(key=lambda a: a["start_time"])

    plans, items, t_appts = [], [], []
    plan_id = 0
    item_id = 0
    ta_seq = 0

    for pat in patients:
        pat_id = pat["id"]
        pp_id = pat_pp.get(pat_id, 2)
        is_nhs = (pp_id == nhs_pp_id)
        apts = pat_apts.get(pat_id, [])

        # Cluster appointments: exam starts a new plan, treatment apts within 8 weeks join it
        clusters = []
        current_cluster = []
        current_start = None

        for apt in apts:
            apt_date = date.fromisoformat(apt["start_time"][:10])
            tx = tx_by_id.get(apt.get("treatment_id"))
            is_exam = tx and int(tx["code"]) in _EXAM_CODES if tx else False
            is_hygiene = tx and int(tx["code"]) == _HYGIENE_CODE if tx else False

            if is_hygiene:
                # Hygiene always gets its own plan
                clusters.append([apt])
                continue

            if is_exam or current_start is None:
                if current_cluster:
                    clusters.append(current_cluster)
                current_cluster = [apt]
                current_start = apt_date
            else:
                if (apt_date - current_start).days <= 56:
                    current_cluster.append(apt)
                else:
                    clusters.append(current_cluster)
                    current_cluster = [apt]
                    current_start = apt_date

        if current_cluster:
            clusters.append(current_cluster)

        pat_site_id = pat.get("site_id", "")

        for cluster in clusters:
            if not cluster:
                continue
            plan_id += 1
            first_apt = cluster[0]
            last_apt = cluster[-1]
            first_date = date.fromisoformat(first_apt["start_time"][:10])
            last_date = date.fromisoformat(last_apt["start_time"][:10])

            would_complete = last_date < TODAY - timedelta(days=7)
            # Private plans have higher in-progress rate (30%) to generate open course value.
            # NHS plans nearly always complete (3%) since item price=0 produces no open courses value.
            ip_prob = 0.03 if is_nhs else 0.30
            in_progress = (
                would_complete
                and (TODAY - last_date).days < 180
                and len(cluster) > 1
                and rng.random() < ip_prob
            )
            completed = would_complete and not in_progress
            completed_at = _iso(last_date) if completed else None

            # Determine highest NHS band in this cluster
            max_nhs_cat = 0
            max_uda = 0
            private_value = 0.0
            plan_items_data = []

            for pos, apt in enumerate(cluster):
                tx_id = apt.get("treatment_id")
                tx = tx_by_id.get(tx_id)
                if not tx:
                    continue
                code = int(tx["code"])
                nhs_cat = tx.get("nhs_treatment_cat") or 0
                uda_b = tx.get("uda_band") or 0

                if is_nhs:
                    price = 0.0
                else:
                    price = fee_map.get((pp_id, tx_id), 0.0)

                private_value += price if not is_nhs else 0.0
                if nhs_cat:
                    max_nhs_cat = max(max_nhs_cat, nhs_cat)
                max_uda = max(max_uda, uda_b)

                item_id += 1
                item_uuid = _u5("tpi", tid, plan_id, pos)
                plan_items_data.append((item_uuid, tx_id, tx, price, nhs_cat, uda_b, apt, pos))

            uda_val = max_uda if is_nhs else 0
            uda_str = str(uda_val) if uda_val > 0 else "0"

            # Nickname
            month_str = first_date.strftime("%B %Y")
            is_hygiene_plan = all(int(tx_by_id.get(a.get("treatment_id"),{}).get("code","0")) == _HYGIENE_CODE
                                  for a in cluster if a.get("treatment_id"))
            if is_hygiene_plan:
                nickname = f"Routine Hygiene - {month_str}"
            elif is_nhs and max_nhs_cat:
                nickname = f"Band {max_nhs_cat} - {month_str}"
            else:
                tx0 = tx_by_id.get(cluster[0].get("treatment_id"), {})
                nickname = f"{tx0.get('description','Treatment')} - {month_str}"

            # plan_acceptance_rate: non-hygiene plans have a chance of no start_date (not accepted)
            if not is_hygiene_plan and plan_acceptance_rate < 1.0 and rng.random() > plan_acceptance_rate:
                start_date_val = None
            else:
                start_date_val = _iso(first_date)

            plans.append({
                "id": plan_id,
                "patient_id": pat_id,
                "practitioner_id": first_apt["practitioner_id"],
                "site_id": pat_site_id,
                "nickname": nickname,
                "completed": completed,
                "completed_at": completed_at,
                "start_date": start_date_val,
                "end_date": _iso(last_date) if completed else None,
                "nhs_uda_value": uda_str,
                "nhs_completed_uda_value": uda_str if completed else "0",
                "private_treatment_value": _fmt(private_value),
                "payment_plan_id": pp_id,
                "last_completed_at": completed_at,
                "created_at": _iso(first_date),
                "updated_at": _iso(last_date),
            })

            for item_uuid, tx_id, tx, price, nhs_cat, uda_b, apt, pos in plan_items_data:
                # ~6% of private items have a referring practitioner (different from treating)
                referrer_id = None
                if not is_nhs and rng.random() < 0.06:
                    candidates = [p for p in all_prac_ids if p != apt["practitioner_id"]]
                    if candidates:
                        referrer_id = rng.choice(candidates)
                items.append({
                    "id": item_uuid,
                    "treatment_plan_id": plan_id,
                    "treatment_id": tx_id,
                    "patient_id": pat_id,
                    "practitioner_id": apt["practitioner_id"],
                    "payment_plan_id": pp_id,
                    "referrer_id": referrer_id,
                    "treatment_appointment_id": _u5("ta", tid, apt["id"], plan_id),
                    "invoice_id": None,  # set later
                    "price": _fmt(price),
                    "duration": 30,
                    "completed": completed,
                    "completed_at": completed_at,
                    "appear_on_invoice": True,
                    "base_chart": None,
                    "charged": completed,
                    "position": pos,
                    "nhs_treatment_cat": nhs_cat if is_nhs else None,
                    "uda_band": uda_b if is_nhs else 0,
                    "nomenclature": tx.get("nomenclature", tx.get("description","")),
                    "patient_nomenclature": tx.get("patient_nomenclature", tx.get("description","")),
                    "notes": None,
                    "region": tx.get("region",""),
                    "surfaces": None,
                    "teeth": None,
                    "created_at": _iso(first_date),
                    "updated_at": _iso(date.fromisoformat(apt["start_time"][:10])),
                })

            # Treatment appointment join records
            for pos, apt in enumerate(cluster):
                ta_seq += 1
                apt_completed = apt["state"] == "completed"
                apt_completed_at = apt.get("completed_at")
                t_appts.append({
                    "id": _u5("ta", tid, apt["id"], plan_id),
                    "appointment_id": apt["id"],
                    "treatment_plan_id": plan_id,
                    "patient_id": pat_id,
                    "position": pos,
                    "bookable": False,
                    "completed": apt_completed,
                    "completed_at": apt_completed_at,
                    "notes": None,
                    "created_at": _iso(date.fromisoformat(apt["start_time"][:10])),
                    "updated_at": _iso(date.fromisoformat(apt["start_time"][:10])),
                })

    return plans, items, t_appts

# ─── INVOICES & ITEMS ─────────────────────────────────────────────────────────

def gen_invoices_and_items(tdef, plans, plan_items_by_plan, patients_by_id, rng):
    tid = tdef["tenant_id"]
    nhs_pp_id = next((pp["id"] for pp in tdef["payment_plans"] if pp.get("nhs")), None)
    admin_user_id = 0
    invoices, items = [], []
    inv_id = 0

    for plan in plans:
        if not plan["completed"]:
            continue
        plan_id = plan["id"]
        pp_id = plan["payment_plan_id"]
        is_nhs = (pp_id == nhs_pp_id)
        pat = patients_by_id.get(plan["patient_id"])
        if not pat:
            continue

        plan_items = plan_items_by_plan.get(plan_id, [])
        completed_date = date.fromisoformat(plan["end_date"][:10]) if plan["end_date"] else TODAY

        inv_id += 1
        inv_ref = f"INV-{inv_id:08d}"

        if is_nhs:
            # All items at £0 + one NHS band charge line
            nhs_cat = int(plan["nhs_uda_value"] or 0)
            # nhs_cat is uda_band (1/3/5/7/12), convert to band number
            if nhs_cat <= 1:   band_num = 1
            elif nhs_cat <= 3: band_num = 2
            else:              band_num = 3
            band_charge = _BAND.get(band_num, 0.0)
            exempt = pat.get("nhs_exemption_code") is not None
            patient_charge = 0.0 if exempt else band_charge
            total_amount = patient_charge
            disc_rate = 0.0
        else:
            total_amount = sum(float(pi["price"]) for pi in plan_items)
            # ~10% of private invoices get a discount (5–15%); invoice.amount stays gross
            disc_rate = rng.uniform(0.05, 0.15) if rng.random() < 0.10 else 0.0
            patient_charge = total_amount * (1 - disc_rate)
            band_num = None

        is_paid = completed_date < TODAY - timedelta(days=30)
        outstanding = 0.0 if is_paid else patient_charge

        invoices.append({
            "id": inv_id,
            "patient_id": plan["patient_id"],
            "account_id": pat["account_id"],
            "site_id": plan["site_id"],
            "practitioner_id": plan["practitioner_id"],
            "payment_plan_id": plan["payment_plan_id"],
            "user_id": admin_user_id,
            "reference": inv_ref,
            "amount": _fmt(total_amount),   # gross; items are reduced when disc_rate > 0
            "amount_outstanding": _fmt(outstanding),
            "paid": is_paid,
            "paid_on": str(completed_date) if is_paid else None,
            "dated_on": str(completed_date),
            "due_on": str(completed_date),
            "nhs_amount": _fmt(patient_charge) if is_nhs else None,
            "payment_terms": "30 days",
            "sent_at": _iso(completed_date) if is_paid else None,
            "footnote": None,
            "created_at": _iso(completed_date),
            "updated_at": _iso(completed_date),
        })

        # Invoice items
        for pos, pi in enumerate(plan_items):
            item_price = float(pi["price"]) * (1 - disc_rate)
            iitem_id = _u5("ii", tid, inv_id, pos)
            items.append({
                "id": iitem_id,
                "invoice_id": inv_id,
                "treatment_plan_id": plan_id,
                "treatment_plan_item_id": pi["id"],
                "practitioner_id": pi["practitioner_id"],
                "user_id": admin_user_id,
                "sundry_id": None,
                "name": pi["nomenclature"],
                "item_price": _fmt(item_price),
                "nhs_charge": 0,
                "quantity": 1,
                "total_price": _fmt(item_price),
                "created_at": _iso(completed_date),
                "updated_at": _iso(completed_date),
            })
            pi["invoice_id"] = inv_id  # mutate in-place; pibp holds references to plan_items dicts

        # NHS band charge line
        if is_nhs and patient_charge > 0:
            items.append({
                "id": _u5("ii", tid, inv_id, "band"),
                "invoice_id": inv_id,
                "treatment_plan_id": plan_id,
                "treatment_plan_item_id": None,
                "practitioner_id": plan["practitioner_id"],
                "user_id": admin_user_id,
                "sundry_id": None,
                "name": f"NHS Band {band_num} Charge",
                "item_price": _fmt(patient_charge),
                "nhs_charge": 1,
                "quantity": 1,
                "total_price": _fmt(patient_charge),
                "created_at": _iso(completed_date),
                "updated_at": _iso(completed_date),
            })

    return invoices, items

# ─── PAYMENTS ─────────────────────────────────────────────────────────────────

def gen_payments(tdef, invoices, rng, plans=None, patients_by_id=None):
    tid = tdef["tenant_id"]
    admin_user = 0
    payments, explanations, allocations = [], [], []
    methods = ["card","card","card","card","card","card","card","card","cash","bank_transfer","insurance","finance"]
    pay_seq = 0
    exp_seq = 0

    for inv in invoices:
        total = float(inv["amount"])
        if total <= 0:
            continue
        inv_date = date.fromisoformat(inv["dated_on"])
        is_lab = False  # simplified: single payment for all

        method = rng.choice(methods)
        pay_seq += 1
        pay_id = pay_seq
        exp_seq += 1
        exp_id = exp_seq

        payments.append({
            "id": pay_id,
            "account_id": inv["account_id"],
            "patient_id": inv["patient_id"],
            "site_id": inv["site_id"],
            "user_id": admin_user,
            "practitioner_id": inv.get("practitioner_id"),
            "payment_plan_id": inv.get("payment_plan_id"),
            "amount": _fmt(total),
            "amount_unexplained": "0.00",
            "method": method,
            "dated_on": str(inv_date),
            "status": "completed",
            "deleted": False,
            "fully_explained": True,
            "reference": None,
            "transaction_number": str(pay_id),
            "explanation_amount": _fmt(total),
            "explanation_comments": None,
            "explanation_id": exp_id,
            "explanation_invoice_id": inv["id"],
            "explanation_invoice_reference": inv["reference"],
            "explanation_payment_reference": pay_id,
            "explanation_user_id": admin_user,
            "created_at": _iso(inv_date),
            "updated_at": _iso(inv_date),
        })
        explanations.append({
            "id": exp_id,
            "payment_id": pay_id,
            "invoice_id": inv["id"],
            "amount": _fmt(total),
            "comments": None,
            "invoice_reference": inv["reference"],
            "payment_reference": pay_id,
            "user_id": admin_user,
            "created_at": _iso(inv_date),
            "updated_at": _iso(inv_date),
        })
        # One allocation per invoice (simplified)
        allocations.append({
            "id": _u5("pa", tid, exp_id),
            "payment_explanation_id": exp_id,
            "invoice_item_id": None,
            "patient_id": inv["patient_id"],
            "amount": _fmt(total),
            "description": None,
            "reversal_of_id": None,
            "transfer_from_id": None, "transfer_from_type": None,
            "transfer_to_id": None, "transfer_to_type": None,
            "created_at": _iso(inv_date),
            "updated_at": _iso(inv_date),
        })

    # Advance deposits for open private plans (~40% chance per qualifying plan)
    if plans and patients_by_id:
        nhs_pp_id_local = next((pp["id"] for pp in tdef["payment_plans"] if pp.get("nhs")), None)
        for plan in plans:
            if plan["completed"]:
                continue
            if plan["payment_plan_id"] == nhs_pp_id_local:
                continue
            pv = float(plan.get("private_treatment_value") or "0")
            if pv < 50.0 or rng.random() > 0.40:
                continue
            dep_amount = pv * rng.uniform(0.2, 0.5)
            plan_date = date.fromisoformat(plan["created_at"][:10])
            dep_date = plan_date + timedelta(days=rng.randint(1, 14))
            pay_seq += 1
            dep_id = pay_seq
            pat = patients_by_id.get(plan["patient_id"])
            payments.append({
                "id": dep_id,
                "account_id": pat["account_id"] if pat else None,
                "patient_id": plan["patient_id"],
                "site_id": plan["site_id"],
                "user_id": admin_user,
                "practitioner_id": plan["practitioner_id"],
                "payment_plan_id": plan["payment_plan_id"],
                "amount": _fmt(dep_amount),
                "amount_unexplained": _fmt(dep_amount),
                "method": rng.choice(["card","card","card","cash","bank_transfer"]),
                "dated_on": str(dep_date),
                "status": "completed",
                "deleted": False,
                "fully_explained": False,
                "reference": None,
                "transaction_number": str(dep_id),
                "explanation_amount": "0.00",
                "explanation_comments": None,
                "explanation_id": None,
                "explanation_invoice_id": None,
                "explanation_invoice_reference": None,
                "explanation_payment_reference": None,
                "explanation_user_id": None,
                "created_at": _iso(dep_date),
                "updated_at": _iso(dep_date),
            })

    return payments, explanations, allocations

# ─── NHS CLAIMS ───────────────────────────────────────────────────────────────

def gen_nhs_claims(tdef, plans, patients_by_id, contracts_by_site, rng):
    tid = tdef["tenant_id"]
    nhs_pp_id = next((pp["id"] for pp in tdef["payment_plans"] if pp.get("nhs")), None)
    if not nhs_pp_id:
        return []
    claims = []
    seq = 0
    this_month = TODAY.replace(day=1)

    for plan in plans:
        if not plan["completed"]:
            continue
        if plan["payment_plan_id"] != nhs_pp_id:
            continue
        pat = patients_by_id.get(plan["patient_id"])
        if not pat:
            continue

        completed_date = date.fromisoformat(plan["end_date"][:10])
        site_id = plan["site_id"]
        contract = contracts_by_site.get(site_id)
        if not contract:
            continue

        uda_b = int(plan["nhs_uda_value"] or 0)
        if uda_b <= 1:   band_num = 1; expected_uda = 1.0
        elif uda_b <= 3: band_num = 2; expected_uda = 3.0
        elif uda_b <= 5: band_num = 2; expected_uda = 5.0
        elif uda_b <= 7: band_num = 2; expected_uda = 7.0
        else:            band_num = 3; expected_uda = 12.0

        exempt = pat.get("nhs_exemption_code") is not None
        patient_charge = 0.0 if exempt else _BAND.get(band_num, 0.0)

        is_this_month = (completed_date >= this_month)

        if is_this_month:
            r = rng.random()
            if r < 0.3:   status = "awaiting_submission"; submitted = None; approved = None
            elif r < 0.7: status = "submitted"; submitted = str(completed_date + timedelta(rng.randint(1,5))); approved = None
            else:          status = "pending"; submitted = str(completed_date + timedelta(2)); approved = None
        else:
            r = rng.random()
            if r < 0.95:
                status = "approved"
                submitted = str(completed_date + timedelta(rng.randint(2,10)))
                approved = str(completed_date + timedelta(rng.randint(10,30)))
            elif r < 0.97:
                status = "rejected"
                submitted = str(completed_date + timedelta(3))
                approved = None
            else:
                status = "submitted"; submitted = str(completed_date + timedelta(5)); approved = None

        awarded_uda = expected_uda if status == "approved" else 0.0
        # UDA value for this contract year
        uda_val_rate = float(contract.get("uda_value", "28.00"))
        dentist_charge = round(expected_uda * uda_val_rate, 2) if status == "approved" else 0.0
        awarded_dentist_charge = dentist_charge if status == "approved" else 0.0
        seq += 1
        claims.append({
            "id": _u5("claim", tid, plan["id"]),
            "contract_id": contract["id"],
            "treatment_plan_id": plan["id"],
            "patient_id": plan["patient_id"],
            "practitioner_id": plan["practitioner_id"],
            "site_id": site_id,
            "uda_band": band_num,
            "expected_uda": expected_uda,
            "awarded_uda": awarded_uda,
            "patient_charge": _fmt(patient_charge),
            "dentist_charge": _fmt(dentist_charge),
            "awarded_dentist_charge": _fmt(awarded_dentist_charge),
            "ni_calculated_dentist_fee": _fmt(round(dentist_charge * 0.9, 2)),
            "ni_calculated_patient_fee": _fmt(patient_charge),
            "status": status,
            "claim_status": status,
            "submitted_date": submitted,
            "approval_date": approved,
            "nhs_updated_at": _iso(approved or submitted or completed_date),
            "sequence_number": f"{seq:06d}",
            "status_comments": "Patient exemption not verified" if status == "rejected" else None,
            "ortho": False,
            "continuation_part_number": None,
            "scot_amount_authorised": None,
            "scot_amount_expected": None,
            "created_at": _iso(completed_date),
            "updated_at": _iso(approved or submitted or completed_date),
        })
    return claims

# ─── PATIENT STATS ────────────────────────────────────────────────────────────

def gen_patient_stats(patients, apts_by_pat, inv_by_pat, pay_by_pat):
    stats = []
    exam_codes_set = {str(c).zfill(4) for c in _EXAM_CODES}
    sp_code = f"{_HYGIENE_CODE:04d}"

    for pat in patients:
        pid = pat["id"]
        apts = sorted(apts_by_pat.get(pid, []), key=lambda a: a["start_time"])
        past_completed = [a for a in apts if a["state"]=="completed" and a["start_time"][:10]<str(TODAY)]
        future_booked  = [a for a in apts if a["state"]=="booked"    and a["start_time"][:10]>=str(TODAY)]
        dna            = [a for a in apts if a["state"]=="did_not_attend"]
        cancelled      = [a for a in apts if a["state"]=="cancelled"]

        def _date_or_none(lst, key=min):
            return lst[0]["start_time"][:10] if lst else None

        exams_past  = [a for a in past_completed if a.get("treatment_id") and
                       True]  # simplified: all past completed count
        sp_past     = [a for a in past_completed]
        exams_fut   = future_booked[:1]

        all_past    = past_completed
        first_apt   = all_past[0]["start_time"][:10]  if all_past  else None
        last_apt    = all_past[-1]["start_time"][:10] if all_past  else None
        next_apt    = future_booked[0]["start_time"][:10] if future_booked else None
        last_fta    = dna[-1]["start_time"][:10]   if dna       else None
        last_cancel = cancelled[-1]["start_time"][:10] if cancelled else None

        invs = inv_by_pat.get(pid, [])
        pays = pay_by_pat.get(pid, [])
        total_inv = sum(float(i["amount"]) for i in invs)
        total_pay = sum(float(p["amount"]) for p in pays)

        stats.append({
            "patient_id": pid,
            "first_appointment_date": first_apt,
            "last_appointment_date": last_apt,
            "next_appointment_date": next_apt,
            "first_exam_date": first_apt,
            "last_exam_date": last_apt,
            "next_exam_date": next_apt,
            "last_scale_and_polish_date": last_apt,
            "next_scale_and_polish_date": next_apt,
            "last_fta_appointment_date": last_fta,
            "last_cancelled_appointment_date": last_cancel,
            "total_paid": _fmt(total_pay),
            "total_invoiced": _fmt(total_inv),
            "nhs_exemption_code": pat.get("nhs_exemption_code"),
            "created_at": _iso(TODAY),
            "updated_at": _iso(TODAY),
        })
    return stats

# ─── RECALLS ──────────────────────────────────────────────────────────────────

def _suppress_rate(days_since_due, rate_recent=0.15, rate_old=0.01, ramp_days=30):
    """Linear ramp: rate_recent at day 0, rate_old at ramp_days+, flat thereafter."""
    t = min(1.0, days_since_due / ramp_days)
    return rate_recent + (rate_old - rate_recent) * t

def gen_recalls(tdef, patients, apts_by_pat, prac_defs_by_id, rng):
    tid = tdef["tenant_id"]
    nhs_pp_id = next((pp["id"] for pp in tdef["payment_plans"] if pp.get("nhs")), None)
    today = date.today()
    reminder_lead = timedelta(days=42)   # first reminder 6 weeks before due
    second_lead   = timedelta(days=14)   # second reminder 2 weeks before due
    recalls = []
    for pat in patients:
        pid = pat["id"]
        pp_id = pat["payment_plan_id"]
        all_apts = sorted(apts_by_pat.get(pid, []), key=lambda a: a["start_time"])
        completed = [a for a in all_apts if a["state"] == "completed"]
        if not completed:
            continue
        last_date = date.fromisoformat(completed[-1]["start_time"][:10])
        interval = 6 if pp_id == nhs_pp_id else 12
        due_date = _add_months(last_date, interval)
        # Skip patients who have reattended after their recall date — Dentally deletes the recall
        has_reattended = any(
            date.fromisoformat(a["start_time"][:10]) >= due_date
            for a in completed
        )
        if has_reattended:
            continue
        # Status — TitleCase to match real API
        status = "Overdue" if due_date < today else "Pending"
        # Reminder dates — sent once the recall is within the reminder window.
        # A small proportion are suppressed to simulate unactioned / partially-actioned recalls.
        # Rate ramps from 15% (due this week / reminder newly due) down to 1% (30+ days ago).
        first_sent  = due_date - reminder_lead
        second_sent = due_date - second_lead
        has_first_window  = first_sent  <= today
        has_second_window = second_sent <= today and due_date < today   # 2nd only sent for overdue

        if has_first_window:
            days_since_first = max(0, (today - first_sent).days)
            p_skip_first = _suppress_rate(days_since_first)
            suppress_first = rng.random() < p_skip_first
        else:
            suppress_first = False

        has_first  = has_first_window  and not suppress_first

        if has_second_window and has_first:
            days_since_second = max(0, (today - second_sent).days)
            p_skip_second = _suppress_rate(days_since_second)
            suppress_second = rng.random() < p_skip_second
        else:
            suppress_second = False

        has_second = has_second_window and has_first and not suppress_second

        first_sent_at  = _iso(first_sent)  if has_first  else None
        second_sent_at = _iso(second_sent) if has_second else None
        last_reminded  = second_sent_at if has_second else first_sent_at
        latest_type    = ("Letter" if has_second else "SMS") if (has_first or has_second) else None
        times_contacted = (2 if has_second else 1) if has_first else 0
        recalls.append({
            "id":                      _u5("recall", tid, pid),
            "patient_id":              pid,
            "site_id":                 pat["site_id"],
            "due_date":                str(due_date),
            "recall_type":             "Dentist",
            "recall_method":           "SMS",
            "status":                  status,
            "appointment_id":          None,
            "prebooked":               False,
            "first_reminder_sent_at":  first_sent_at,
            "first_reminder_type":     "SMS"    if has_first  else None,
            "second_reminder_sent_at": second_sent_at,
            "second_reminder_type":    "Letter" if has_second else None,
            "last_reminded_at":        last_reminded,
            "latest_reminder_type":    latest_type,
            "times_contacted":         times_contacted,
            "run_date":                None,
            "workflow_status":         "unprocessed",
            "workflow_stage_id":       None,
            "first_reminder_id":       None,
            "second_reminder_id":      None,
        })
    return recalls

# ─── PATIENT RECALL DATE ENRICHMENT ─────────────────────────────────────────
# Called after appointments are generated; backfills dentist_recall_date and
# hygienist_recall_date onto patient dicts based on actual last attended exams.

def enrich_patient_recall_dates(patients, apts_by_pat, tx_by_code, pp_by_id):
    exam_tx_ids  = {tx["id"] for tx in tx_by_code.values() if int(tx["code"]) in _EXAM_CODES}
    hygiene_tx_ids = {tx["id"] for tx in tx_by_code.values() if int(tx["code"]) == _HYGIENE_CODE}
    for pat in patients:
        pp           = pp_by_id.get(pat["payment_plan_id"], {})
        dr_interval  = pp.get("dentist_recall_interval", 12)
        hr_interval  = pp.get("hygienist_recall_interval", 6)
        completed    = [a for a in apts_by_pat.get(pat["id"], [])
                        if a["state"] == "completed"]
        exams        = [a for a in completed if a.get("treatment_id") in exam_tx_ids]
        hygiene_apts = [a for a in completed if a.get("treatment_id") in hygiene_tx_ids]
        if exams:
            last_exam_d = date.fromisoformat(max(a["start_time"][:10] for a in exams))
            pat["dentist_recall_date"]   = str(_add_months(last_exam_d, dr_interval))
        else:
            pat["dentist_recall_date"]   = None
        if hygiene_apts:
            last_hyg_d = date.fromisoformat(max(a["start_time"][:10] for a in hygiene_apts))
            pat["hygienist_recall_date"] = str(_add_months(last_hyg_d, hr_interval))
        else:
            pat["hygienist_recall_date"] = None

# ─── PATIENT REFERRALS ───────────────────────────────────────────────────────

def gen_patient_referrals(tdef, patients, apts_by_pat, rng):
    tid      = tdef["tenant_id"]
    site_ids = [s["id"] for s in tdef["sites"]]
    ref_types = ["Patient", "Specialist", "Internal"]
    referrals = []
    ref_id    = tid * 100000

    # Dentists/specialists per site for internal referrals
    site_clinicians = {}
    for p in tdef["_prac_defs"]:
        if p["role"] in ("dentist", "orthodontist", "specialist"):
            site_clinicians.setdefault(p["site_id"], []).append(p["id"])

    for pat in patients:
        if rng.random() >= 0.15:
            continue
        pat_id = pat["id"]
        appts  = sorted(apts_by_pat.get(pat_id, []), key=lambda a: a["start_time"])
        if not appts:
            continue
        first_apt = appts[0]
        ref_id   += 1
        ref_type  = rng.choice(ref_types)
        site_id   = pat.get("site_id") or rng.choice(site_ids)
        ref_dt    = first_apt["start_time"]
        # Internal referrals have a referred practitioner (different from the patient's dentist)
        referred_prac_id = None
        if ref_type == "Internal":
            candidates = [pid for pid in site_clinicians.get(site_id, [])
                          if pid != pat.get("dentist_id")]
            if candidates:
                referred_prac_id = rng.choice(candidates)
        referrals.append({
            "id":                        ref_id,
            "patient_id":                pat_id,
            "site_id":                   site_id,
            "user_id":                   first_apt["user_id"],
            "reference":                 f"REF{ref_id:07d}",
            "status":                    "active",
            "referrable_type":           ref_type,
            "services_appointment_id":   None,
            "additional_information":    None,
            "consented_by_patient":      True,
            "referred_practitioner_id":  referred_prac_id,
            "referred_site_id":          None,
            "created_at":                ref_dt,
            "updated_at":                ref_dt,
        })
    return referrals


# ─── ACCOUNTS ────────────────────────────────────────────────────────────────

def gen_accounts(patients, invoices, payments):
    inv_by_pat  = {}
    for inv in invoices:
        inv_by_pat.setdefault(inv["patient_id"], []).append(float(inv["amount"]))
    pay_by_pat  = {}
    for pay in payments:
        pay_by_pat.setdefault(pay["patient_id"], []).append(float(pay["amount"]))

    accounts = []
    for pat in patients:
        pid      = pat["id"]
        total_inv = sum(inv_by_pat.get(pid, []))
        total_pay = sum(pay_by_pat.get(pid, []))
        balance   = round(total_inv - total_pay, 2)
        accounts.append({
            "id":                            pat["account_id"],
            "patient_id":                    pid,
            "patient_name":                  f"{pat['first_name']} {pat['last_name']}",
            "current_balance":               _fmt(balance),
            "opening_balance":               "0.00",
            "planned_nhs_treatment_value":   "0.00",
            "planned_private_treatment_value": "0.00",
        })
    return accounts


# ─── GENERATE TENANT ─────────────────────────────────────────────────────────

def generate_tenant(tdef):
    rng = random.Random(tdef["tenant_id"] * 9973)
    tid = tdef["tenant_id"]

    tx_raw = _TX + (_TX_ORTHO if tdef.get("has_ortho") else []) + _TX_TCO
    tx_list   = gen_treatments(tdef, tx_raw)
    tx_cats   = gen_treatment_categories(tdef)
    pp_list   = tdef["payment_plans"]
    fees      = gen_fees(tdef, tx_list, pp_list)
    users, practitioners = gen_users_and_practitioners(tdef)
    diary_entries, diary_breaks = gen_diary(tdef, tdef["_prac_defs"])

    diary_set = {(e["practitioner_id"], e["date"]) for e in diary_entries}
    prac_defs_by_id = {p["id"]: p for p in tdef["_prac_defs"]}

    tx_by_code = {int(t["code"]): t for t in tx_list}
    tx_by_id   = {t["id"]: t for t in tx_list}

    # Fee lookup: {(pp_id, tx_id): price}
    fee_map = {(f["payment_plan_id"], f["treatment_id"]): float(f["price_one"]) for f in fees}

    rooms   = gen_rooms(tdef)
    patients = gen_patients(tdef, rng)
    appointments = gen_appointments(tdef, patients, diary_set, prac_defs_by_id, tx_by_code, rooms, rng)

    # Backfill dentist_recall_date / hygienist_recall_date onto patient dicts now
    # that we know which appointments each patient actually attended.
    _apts_by_pat_tmp = {}
    for a in appointments:
        _apts_by_pat_tmp.setdefault(a["patient_id"], []).append(a)
    pp_by_id = {pp["id"]: pp for pp in tdef["payment_plans"]}
    enrich_patient_recall_dates(patients, _apts_by_pat_tmp, tx_by_code, pp_by_id)

    plans, plan_items, treatment_appts = gen_treatment_plans_and_items(
        tdef, patients, appointments, tx_by_id, fee_map, rng)

    # Index plan_items by plan_id
    pibp = {}
    for pi in plan_items:
        pibp.setdefault(pi["treatment_plan_id"], []).append(pi)

    patients_by_id = {p["id"]: p for p in patients}
    invoices, inv_items = gen_invoices_and_items(tdef, plans, pibp, patients_by_id, rng)

    payments, explanations, allocations = gen_payments(tdef, invoices, rng, plans=plans, patients_by_id=patients_by_id)

    contracts_by_site = {c["site_id"]: c for c in tdef.get("contracts",[]) if c.get("active")
                         and float(c.get("target","0")) > 0}
    nhs_claims = gen_nhs_claims(tdef, plans, patients_by_id, contracts_by_site, rng)

    apts_by_pat = {}
    for a in appointments:
        apts_by_pat.setdefault(a["patient_id"], []).append(a)
    inv_by_pat = {}
    for i in invoices:
        inv_by_pat.setdefault(i["patient_id"], []).append(i)
    pay_by_pat = {}
    for p in payments:
        pay_by_pat.setdefault(p["patient_id"], []).append(p)

    patient_stats      = gen_patient_stats(patients, apts_by_pat, inv_by_pat, pay_by_pat)
    recalls            = gen_recalls(tdef, patients, apts_by_pat, prac_defs_by_id, rng)
    patient_referrals  = gen_patient_referrals(tdef, patients, apts_by_pat, rng)

    # Link booked recall appointments back to their recall records
    _recall_apt_by_patient = {
        a["patient_id"]: str(a["id"])
        for a in appointments
        if a.get("reason") == "Recall Examination" and a.get("state") == "booked"
    }
    for r in recalls:
        booked_apt = _recall_apt_by_patient.get(r["patient_id"])
        if booked_apt:
            r["appointment_id"] = booked_apt

    return {
        "practice":            tdef["practice"],
        "sites":               [{**{"email_address": None, "nickname": None, "address_line_2": None, "website": None, "logo_url": None, "default_payment_plan_id": None}, **s, "practice_id": tdef["practice"]["id"]} for s in tdef["sites"]],
        "rooms":               rooms,
        "users":               users,
        "practitioners":       practitioners,
        "payment_plans":       pp_list,
        "fees":                fees,
        "treatments":          tx_list,
        "treatment_categories": tx_cats,
        "contracts":           tdef.get("contracts", []),
        "acquisition_sources": tdef["acquisition_sources"],
        "cancellation_reasons": tdef["cancellation_reasons"],
        "sundries":            tdef["sundries"],
        "waiting_lists":       tdef["waiting_lists"],
        "diary_entries":       diary_entries,
        "diary_breaks":        diary_breaks,
        "patients":            patients,
        "appointments":        appointments,
        "treatment_appts":     treatment_appts,
        "treatment_plans":     plans,
        "treatment_plan_items": plan_items,
        "invoices":            invoices,
        "invoice_items":       inv_items,
        "payments":            payments,
        "payment_explanations": explanations,
        "payment_allocations": allocations,
        "nhs_claims":          nhs_claims,
        "patient_stats":       patient_stats,
        "recalls":             recalls,
        "patient_referrals":   patient_referrals,
        "accounts":            gen_accounts(patients, invoices, payments),
    }


def main():
    out = Path(__file__).parent / "data"
    out.mkdir(exist_ok=True)

    first_tx = None
    first_cats = None

    for i, tdef in enumerate(TENANT_DEFS, 1):
        print(f"Generating tenant {i} ({tdef['practice']['name']})...", flush=True)
        data = generate_tenant(tdef)

        path = out / f"tenant_{i}.json"
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, default=str)

        if i == 1:
            first_tx   = data["treatments"]
            first_cats = data["treatment_categories"]

        n = {k: len(data[k]) for k in
             ("patients","appointments","treatment_plans","invoices","nhs_claims","diary_entries")}
        print(f"  patients={n['patients']}  apts={n['appointments']}  "
              f"plans={n['treatment_plans']}  invoices={n['invoices']}  "
              f"claims={n['nhs_claims']}  diary={n['diary_entries']}")
        print(f"  -> {path}")

    shared = {"treatments": first_tx, "treatment_categories": first_cats}
    with open(out / "shared.json", "w", encoding="utf-8") as f:
        json.dump(shared, f, default=str)
    print("Done.")


if __name__ == "__main__":
    main()
