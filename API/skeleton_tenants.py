"""Structural test tenants for the hierarchy work. DEV ONLY.

==> THESE ARE NOT DEMO DATA AND MUST NEVER LOOK LIKE IT. <== T11 and T12 are built to be
shown to a prospect; every number in them is tuned so the practice reads as a going concern.
These four are the opposite: two practitioners and two patients each, so that a roll-up which
sums when it should average, or averages when it should sum, produces an obviously wrong
number rather than a plausible one.

They exist to exercise the hierarchy, which needs a SHAPE rather than a volume:

    group 20 "Skeleton Group"
      North  ── Manchester ── t21 (2 sites), t22 (3 sites)   two practices in one area
             └─ Leeds      ── t23 (2 sites)                  a second area in the region
      South  ── London     ── t24 (2 sites)                   a second region in the group

Nine sites over four practices, so every level above the site has more than one child. A
level with a single child cannot tell SUM from MAX, and that is the roll-up mistake most
worth catching.

==> THE NUMBERS ARE DELIBERATELY UNEVEN. <== If every practitioner billed the same, a
measure that averaged where it should sum would give the right answer by accident at every
level. Patient splits across sites are lopsided for the same reason.

Tenant numbering: synthetic tenants are < 100 by convention, real practices are 100 and up.
`seed_onelake.py` refuses to seed anything < 100 into the prod lakehouse.
"""
from generate_data import _acq, _cr, _pp, _sundry, _u5, _wl

GROUP_CLIENT_ID = 20
GROUP_NAME = 'Skeleton Group'

# (tenant, region, area) -- the shape above, fed to Audit.usp_Form_Client_Group one call per
# (region, area) pair so two tenants can share an area.
GROUP_LAYOUT = [
    (('North', 'Manchester'), [21, 22]),
    (('North', 'Leeds'), [23]),
    (('South', 'London'), [24]),
]


def _practice(tid, name, town, postcode, domain):
    return {
        'id': _u5('practice', tid), 'name': name, 'nhs': False,
        'address_line_1': '1 Test Street', 'address_line_2': None,
        'town': town, 'postcode': postcode,
        'phone_number': '0100 000 %04d' % tid, 'email_address': 'info@%s' % domain,
        'patient_email_address': 'patients@%s' % domain,
        'website': 'https://%s' % domain, 'logo_url': None,
        'slug': name.lower().replace(' ', '-'), 'time_zone': 'Europe/London',
        'medical_history_expiry_days': 365,
        'custom_patient_field_label_1': None, 'custom_patient_field_label_2': None,
        'oh_mon_open': '09:00', 'oh_mon_close': '17:00',
        'oh_tues_open': '09:00', 'oh_tues_close': '17:00',
        'oh_wed_open': '09:00', 'oh_wed_close': '17:00',
        'oh_thur_open': '09:00', 'oh_thur_close': '17:00',
        'oh_fri_open': '09:00', 'oh_fri_close': '17:00',
        'oh_sat_open': None, 'oh_sat_close': None,
        'oh_sun_open': None, 'oh_sun_close': None,
    }


def _site(tid, suffix, name, town, postcode):
    return {
        'id': 't%d-%s' % (tid, suffix), 'name': name, 'active': True,
        'address_line_1': '1 Test Street', 'town': town, 'postcode': postcode,
        'phone_number': '0100 001 %04d' % tid, 'email': 'clinic@t%d.test' % tid,
        'monday_open': '09:00', 'monday_close': '17:00',
        'tuesday_open': '09:00', 'tuesday_close': '17:00',
        'wednesday_open': '09:00', 'wednesday_close': '17:00',
        'thursday_open': '09:00', 'thursday_close': '17:00',
        'friday_open': '09:00', 'friday_close': '17:00',
        'saturday_open': None, 'saturday_close': None,
    }


def _prac(pid, first, last, role, custom_role, fte, site_id, gdc, days):
    """One practitioner. FTE and working days differ per person on purpose -- identical
    practitioners make a wrong roll-up look right."""
    return {
        'id': pid, 'first_name': first, 'last_name': last, 'title': 'Dr',
        'role': role, 'custom_role': custom_role, 'fte': fte,
        'site_id': site_id, 'gdc_number': gdc, 'nhs_pct': 0.0,
        'work_days': days, 'start_time': '09:00', 'end_time': '17:00',
        'late_days': [], 'late_end': None, 'pp_ids': [1, 2],
        'performs_nhs': False, 'active': True,
    }


def _skeleton(tid, name, town, postcode, sites, pracs, split, n_patients):
    domain = 't%d.test' % tid
    first_site = sites[0]['id']
    return {
        'tenant_id': tid, 'nhs': False, 'has_ortho': False,
        'price_mult': 1.0, 'n_patients': n_patients,
        'domain': domain,
        'practice': _practice(tid, name, town, postcode, domain),
        'sites': sites,
        'payment_plans': [
            _pp(1, 'NHS', nhs=True),
            _pp(2, 'Private'),
        ],
        'contracts': [],
        # String ids, as the real profiles use: gen_patients substring-tests the id when it
        # weights acquisition sources, so an int id raises on the first patient.
        'acquisition_sources': [_acq('acq-%d-01' % tid, 'Walk-in'),
                                _acq('acq-%d-02' % tid, 'Google Search')],
        'cancellation_reasons': [_cr('cr-%d-01' % tid, 'Patient cancelled'),
                                 _cr('cr-%d-02' % tid, 'Practice cancelled')],
        'sundries': [_sundry(tid, first_site, 'Sundry', '10.00')],
        'waiting_lists': [_wl(tid, first_site, 'General', 14)],
        '_prac_defs': pracs,
        '_pp_weights': {2: 100.0},
        '_site_patient_split': split,
        '_params': {},
    }


# ── t21 · Manchester · 2 sites ───────────────────────────────────────────────
T21 = _skeleton(
    21, 'Skeleton Alpha', 'Manchester', 'M1 1AA',
    sites=[_site(21, 'a', 'Alpha Central', 'Manchester', 'M1 1AA'),
           _site(21, 'b', 'Alpha North', 'Manchester', 'M8 2BB')],
    pracs=[_prac(1, 'Alice', 'Archer', 'dentist', 'Principal', 1.00, 't21-a', '2100001',
                 [0, 1, 2, 3, 4]),
           _prac(2, 'Ben', 'Burton', 'hygienist', 'Hygienist', 0.40, 't21-b', '2100002',
                 [0, 2])],
    split={'t21-a': 0.75, 't21-b': 0.25},
    n_patients=2)

# ── t22 · Manchester · 3 sites, shares an area with t21 ──────────────────────
# Three sites because the per-site duplication in Fact_Metric_Actuals only shows above two.
T22 = _skeleton(
    22, 'Skeleton Bravo', 'Manchester', 'M2 2AA',
    sites=[_site(22, 'a', 'Bravo Central', 'Manchester', 'M2 2AA'),
           _site(22, 'b', 'Bravo East', 'Manchester', 'M11 3CC'),
           _site(22, 'c', 'Bravo West', 'Manchester', 'M16 4DD')],
    pracs=[_prac(1, 'Carla', 'Cross', 'dentist', 'Associate', 0.80, 't22-a', '2200001',
                 [0, 1, 2]),
           _prac(2, 'Dan', 'Deakin', 'dentist', 'Associate', 0.60, 't22-c', '2200002',
                 [3, 4])],
    split={'t22-a': 0.50, 't22-b': 0.25, 't22-c': 0.25},
    n_patients=2)

# ── t23 · Leeds · a second area in the North region ──────────────────────────
T23 = _skeleton(
    23, 'Skeleton Charlie', 'Leeds', 'LS1 1AA',
    sites=[_site(23, 'a', 'Charlie Central', 'Leeds', 'LS1 1AA'),
           _site(23, 'b', 'Charlie South', 'Leeds', 'LS11 2BB')],
    pracs=[_prac(1, 'Eve', 'Ellis', 'dentist', 'Principal', 0.90, 't23-a', '2300001',
                 [1, 2, 3, 4]),
           _prac(2, 'Finn', 'Frost', 'hygienist', 'Hygienist', 0.20, 't23-b', '2300002',
                 [1])],
    split={'t23-a': 0.60, 't23-b': 0.40},
    n_patients=2)

# ── t24 · London · a second region in the group ──────────────────────────────
T24 = _skeleton(
    24, 'Skeleton Delta', 'London', 'EC1 1AA',
    sites=[_site(24, 'a', 'Delta Central', 'London', 'EC1 1AA'),
           _site(24, 'b', 'Delta West', 'London', 'W1 2BB')],
    pracs=[_prac(1, 'Gail', 'Grant', 'dentist', 'Associate', 0.50, 't24-a', '2400001',
                 [0, 4]),
           _prac(2, 'Hugo', 'Hale', 'dentist', 'Associate Specialist', 0.10, 't24-b',
                 '2400002', [2])],
    split={'t24-a': 0.80, 't24-b': 0.20},
    n_patients=2)


SKELETON_TENANTS = {21: T21, 22: T22, 23: T23, 24: T24}
