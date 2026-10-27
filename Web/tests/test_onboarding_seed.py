"""Unit tests for Web/onboarding_seed.py -- the derivation rules, on the live practice's shapes.

Every fixture below is REAL data from tenant 100, so a rule that stops reproducing the owner's
own hand-curated answer fails here rather than on a customer's first morning.

==> THE SEEDER WRITES A CUSTOMER'S OPENING IMPRESSION. <== There is no second first look, and
nothing downstream validates what it writes: a wrong role silently mis-scales every target
under it, and a wrong FTE mis-scales them again.
"""
import datetime as dt
import os

os.environ.setdefault('TENANT_ID', 'test-tenant')
os.environ.setdefault('CLIENT_ID', 'test-client')
os.environ.setdefault('CLIENT_SECRET', 'test-secret')
os.environ.setdefault('FABRIC_SERVER', 'test-server')
os.environ.setdefault('FABRIC_DB', 'WH_Test')

import onboarding_seed as seed  # noqa: E402


# Tenant 100, active clinicians: (practitioner_id, pk, name, dentally_role, patients_owned).
# The pk values are stand-ins; nothing under test joins on them.
MAPLE = [
    (11620, 2, 'Craig Jack', 'dentist', 1582),
    (11619, 1, 'Stephen Roberts', 'dentist', 1713),
    (264905, 7, 'David Mason', 'dentist', 1715),
    (254470, 6, 'Tessa Clarke', 'dentist', 993),
    (83319, 5, 'Mark McAfee', 'dentist', 783),
    (11624, 3, 'Rahim Kanji', 'dentist', 40),
    (11648, 4, 'Oliver Hinton', 'dentist', 8),
    (51234, 8, 'Rhonda Cormac', 'dentist', 5),
    (11967, 9, 'Nuha Zeiton', 'dentist', 3),
    (11652, 10, 'Katie Roddy', 'hygienist', 0),
    (11651, 11, 'Katherine Walker', 'hygienist', 0),
    (31076, 12, 'Lily McFarland', 'hygienist', 0),
    (11653, 13, 'Maxine Adie.', 'hygienist', 0),
    (358289, 14, 'Maryam Gulabshah', 'hygienist', 0),
    (11972, 15, 'Locum user', 'hygienist', 0),
]

CRAIG, STEPHEN, DAVID, TESSA, MARK = 11620, 11619, 264905, 254470, 83319
RAHIM, OLIVER, RHONDA, NUHA = 11624, 11648, 51234, 11967


# ── Step 1: roles ─────────────────────────────────────────────────────────────

def test_the_cascade_reproduces_the_owners_own_assignment():
    """The whole point. The owner said: Craig as he is, Stephen/Mark/David/Tess as associates,
    the other dentists as associate specialists, hygienists as they are."""
    roles = seed.derive_roles(MAPLE, principal_id=CRAIG)
    assert roles[CRAIG] == seed.ROLE_PRINCIPAL
    for pid in (STEPHEN, DAVID, TESSA, MARK):
        assert roles[pid] == seed.ROLE_ASSOCIATE, pid
    for pid in (RAHIM, OLIVER, RHONDA, NUHA):
        assert roles[pid] == seed.ROLE_SPECIALIST, pid
    assert roles[11652] == seed.ROLE_HYGIENIST
    assert len(roles) == 15


def test_the_split_sits_in_a_20x_gap_so_the_threshold_is_not_tuned():
    """Mark holds 783 patients and Rahim 40. ==> ANY THRESHOLD IN THAT GAP GIVES THE SAME
    ANSWER. <== If a future change makes this test the only thing holding the split, the margin
    is what says the rule is real rather than fitted."""
    median = 783.0                      # median of the nine dentists' lists
    threshold = median * seed.SPECIALIST_LIST_FRACTION
    assert 40 < threshold < 783
    assert threshold / 40 > 1.9         # clear of the largest session worker
    assert 783 / threshold > 9.9        # clear of the smallest list-holder


def test_no_principal_leaves_every_dentist_an_associate():
    """The office-manager signup. The owner: we cannot assign Principal to any."""
    roles = seed.derive_roles(MAPLE, principal_id=None)
    assert seed.ROLE_PRINCIPAL not in roles.values()
    assert roles[CRAIG] == seed.ROLE_ASSOCIATE
    assert roles[RAHIM] == seed.ROLE_SPECIALIST      # the list rule still applies


def test_a_hygienist_is_never_reclassified_by_list_size():
    """Hygienists own no patients, so the list rule would make every one of them a specialist.
    The role test has to come first."""
    roles = seed.derive_roles(MAPLE, principal_id=CRAIG)
    hygienists = [p for p, _pk, _n, r, _o in MAPLE if r == 'hygienist']
    assert all(roles[p] == seed.ROLE_HYGIENIST for p in hygienists)


def test_a_principal_who_is_a_hygienist_stays_a_hygienist():
    """Order matters and this is the collision: the signup could be linked to a hygienist."""
    roles = seed.derive_roles(MAPLE, principal_id=11652)
    assert roles[11652] == seed.ROLE_HYGIENIST


def test_a_single_dentist_practice_gets_no_specialists():
    """One dentist is their own median, so the threshold is 10% of their own list and they
    cannot fall under it. A lone associate must not be classed a session worker."""
    solo = [(1, 1, 'Only Dentist', 'dentist', 900), (2, 2, 'A Hygienist', 'hygienist', 0)]
    roles = seed.derive_roles(solo, principal_id=None)
    assert roles[1] == seed.ROLE_ASSOCIATE


def test_locums_are_spotted_by_name_because_nothing_else_says_so():
    assert seed.is_locum('Locum user') is True
    assert seed.is_locum('LOCUM Hygienist') is True
    assert seed.is_locum('Craig Jack') is False
    assert seed.is_locum(None) is False


# ── find_principal: the one lookup that only ever runs on a brand-new tenant ──

class _Cur(object):
    """Two queries in order: the tenant's app accounts, then the practitioner match."""

    def __init__(self, accounts, matches):
        self.accounts, self.matches, self._n = accounts, matches, 0

    def execute(self, sql, *args):
        self._n += 1
        return self

    def fetchall(self):
        return self.accounts if self._n == 1 else self.matches


def test_the_signup_is_matched_on_email_not_on_practitioner_name():
    """==> Audit.usp_Provision_Tenant INSERTS Practitioner_Full_Name AS NULL. <== It runs at
    STEP 0 of onboarding, before any Dentally data exists, so it cannot name a practitioner even
    in principle. A lookup keyed on that column returns None on the single run this exists for,
    and every dentist silently defaults to Associate."""
    cur = _Cur([('craig@maple.example', None)], [(11620,)])
    assert seed.find_principal(cur, 100) == 11620


def test_several_accounts_means_we_cannot_tell_which_came_first():
    """The live practice: six accounts, three matching a dentist. None is the honest answer."""
    cur = _Cur([('a@x.example', None), ('b@x.example', None)], [(11620,)])
    assert seed.find_principal(cur, 100) is None


def test_an_office_manager_signup_yields_no_principal():
    """Their email matches no active dentist. The owner: we cannot assign Principal to any."""
    cur = _Cur([('office@maple.example', None)], [])
    assert seed.find_principal(cur, 100) is None


def test_an_ambiguous_match_is_refused_rather_than_guessed():
    """Two dentists sharing a practice mailbox. Picking one at random assigns a role, an FTE
    band and a target set to the wrong person."""
    cur = _Cur([('reception@maple.example', None)], [(11620,), (11619,)])
    assert seed.find_principal(cur, 100) is None


# ── Step 2: FTE ───────────────────────────────────────────────────────────────

def _weeks(pid, hours_per_week, n_weeks):
    return [(pid, w, hours_per_week) for w in range(n_weeks)]


def test_a_regular_worker_uses_the_median_week():
    rows = _weeks(DAVID, 32.33, 25)
    assert seed.derive_fte(rows)[DAVID] == round(32.33 / 37.5, 2)      # 0.86


def test_leave_does_not_drag_a_full_timer_down():
    """==> THE MEDIAN IS OVER WEEKS ACTUALLY WORKED. <== Three weeks off in the window must not
    read as a 0.75 FTE; only non-zero weeks are passed in, and the median ignores the tail."""
    rows = _weeks(1, 37.5, 20) + [(1, 90 + i, 8.0) for i in range(3)]
    assert seed.derive_fte(rows)[1] == 1.0


def test_a_sporadic_worker_is_averaged_over_the_whole_window():
    """Rahim worked 13 of 26 weeks. The median of those 13 measures the week he DOES work and
    overstated him two-fold; dividing his total across all 26 weeks lands on the owner's 0.10."""
    rows = _weeks(RAHIM, 7.5, 13)
    fte = seed.derive_fte(rows)[RAHIM]
    assert fte == round(7.5 * 13 / (37.5 * 26), 2)                     # 0.10
    assert fte < round(7.5 / 37.5, 2)                                  # not the 0.20 median


def test_the_regular_sporadic_boundary_is_where_it_says_it_is():
    """75% of 26 weeks is 19.5, so 20 weeks is regular and 19 is sporadic. A worker either side
    of it gets a materially different number, which is why the line is asserted."""
    assert seed.derive_fte(_weeks(1, 20.0, 20))[1] == round(20.0 / 37.5, 2)
    assert seed.derive_fte(_weeks(2, 20.0, 19))[2] == round(20.0 * 19 / (37.5 * 26), 2)


def test_a_practitioner_with_no_rostered_hours_is_absent_not_zero():
    """Absent means 'write nothing'; Dim_Practitioners defaults a missing FTE to 1.0, so an
    accidental 0.0 and an accidental omission fail in opposite directions."""
    assert seed.derive_fte([]) == {}


def test_derived_fte_tracks_the_owners_entered_values():
    """The regression that matters: mean absolute error against the hand-entered set.
    (median week hours, entered FTE) for the eleven regular workers."""
    entered = [(32.33, 0.86), (26.83, 0.86), (21.50, 0.60), (20.50, 0.66), (18.00, 0.55),
               (16.00, 0.46), (14.00, 0.40), (13.92, 0.40), (13.00, 0.36), (10.00, 0.26),
               (4.00, 0.10)]
    rows, expect = [], []
    for i, (hrs, owner) in enumerate(entered):
        rows += _weeks(i, hrs, 25)
        expect.append(owner)
    fte = seed.derive_fte(rows)
    errors = [abs(fte[i] - owner) for i, owner in enumerate(expect)]
    assert sum(errors) / len(errors) < 0.06, dict(zip(range(len(expect)), errors))
    assert max(errors) <= 0.14          # the two principals, whose admin time is off-diary


# ── Step 3: associate percentage ──────────────────────────────────────────────

def test_only_associates_and_specialists_get_a_percentage():
    """Principals take the profit, hygienists are salaried. Both must be ABSENT, not zero --
    a 0% rate would hand every penny of their revenue to the practice as profit."""
    roles = seed.derive_roles(MAPLE, principal_id=CRAIG)
    pct = seed.derive_associate_pct(roles)
    assert pct[STEPHEN] == 50.0 and pct[RAHIM] == 50.0
    assert CRAIG not in pct
    assert 11652 not in pct


# ── Step 4: plan rates ────────────────────────────────────────────────────────

# (payment_plan_id, name, exams, free_exams) -- tenant 100, trailing year.
PLAN_SIGNAL = [
    (1, 'Private', 4241, 303),
    (2, 'NHS', 2408, 2054),
    (3, 'Denplan C', 1227, 1224),
    (4, 'Denplan Essentials A', 927, 909),
    (5, 'Denplan B', 590, 588),
    (6, 'Denplan D', 346, 346),
    (7, 'Denplan Essentials B', 249, 238),
    (8, 'Denplan A', 176, 174),
    (9, 'Referral', 3, 2),
    (10, 'Denplan E', 48, 48),
    (11, 'Denplan Children', 16, 16),
    (12, 'IRH Fees', 9, 0),
]


def test_the_free_exam_signal_finds_exactly_the_plans_the_owner_rated():
    """Eight plans carry a capitation rate in Input.Plan_Capitation_Rate. No more, no fewer."""
    found = {name for _id, name, _m, _c in seed.derive_plans(PLAN_SIGNAL)}
    assert found == {'Denplan A', 'Denplan B', 'Denplan C', 'Denplan D', 'Denplan E',
                     'Denplan Children', 'Denplan Essentials A', 'Denplan Essentials B'}


def test_nhs_is_the_false_positive_and_is_excluded_twice_over():
    """==> NHS EXAMS ARE FREE TO THE PATIENT TOO. <== It ran 85.3% free on live data, which the
    threshold alone rejects -- but only by ten points, and NHS_Revenue is not populated on the
    daily aggregate so it cannot discriminate. The name guard is the second line."""
    assert 100.0 * 2054 / 2408 < seed.PLAN_FREE_EXAM_PCT
    nhs_at_100 = [(2, 'NHS', 2408, 2408)]
    assert seed.derive_plans(nhs_at_100) == []
    assert seed._looks_nhs('NHS') and seed._looks_nhs('nhs band 1')
    assert not seed._looks_nhs('Denplan Essentials A')


def test_a_tiny_plan_is_not_judged_on_three_exams():
    """Referral is 66.7% free off 3 exams -- noise either way. It must fail on the count."""
    assert seed.derive_plans([(9, 'Referral', 3, 3)]) == []


def test_a_real_childrens_plan_survives_the_minimum():
    """16 exams in a year, and genuinely a capitation plan. A minimum of 20 would drop it."""
    assert len(seed.derive_plans([(11, 'Denplan Children', 16, 16)])) == 1


def test_every_plan_gets_the_same_rate_and_cross_charge():
    """Deliberate. A wrong specific number is harder to spot than an obviously uniform one."""
    for _id, _name, monthly, cross in seed.derive_plans(PLAN_SIGNAL):
        assert monthly == 35.0 and cross == 29.0


# ── Step 5: targets ───────────────────────────────────────────────────────────

def test_sample_values_parse_the_way_the_settings_screen_writes_them():
    assert seed.parse_sample('£600,000') == 600000.0
    assert seed.parse_sample('55%') == 55.0
    assert seed.parse_sample('1,200') == 1200.0
    assert seed.parse_sample('2') == 2.0
    assert seed.parse_sample(None) is None
    assert seed.parse_sample('-') is None


def test_a_percentage_target_stores_as_a_whole_number():
    """The DAX divides by 100 (tRate100) and the live practice stores 4 for a 4% deposit ratio.
    Storing 0.04 would show a 0.04% target and read as a broken report, not a wrong one."""
    assert seed.parse_sample('10%') == 10.0


# One role's worth of inputs: hours {pid: (hist, fwd)} and revenue {pid: trailing}.
HOURS = {CRAIG: (1007.0, 1099.0), STEPHEN: (1224.0, 1439.0), DAVID: (1186.0, 1639.0),
         TESSA: (605.0, 683.0), MARK: (697.0, 793.0)}
REVENUE = {CRAIG: 230000.0, STEPHEN: 261172.0, DAVID: 125922.0,
           TESSA: 75055.0, MARK: 128216.0}
FTE = {CRAIG: 0.55, STEPHEN: 0.72, DAVID: 0.86, TESSA: 0.35, MARK: 0.37}
ROLES = {CRAIG: seed.ROLE_PRINCIPAL, STEPHEN: seed.ROLE_ASSOCIATE,
         DAVID: seed.ROLE_ASSOCIATE, TESSA: seed.ROLE_ASSOCIATE, MARK: seed.ROLE_ASSOCIATE}


def test_the_role_value_is_per_fte_not_the_capacity():
    """==> THE DAX MULTIPLIES A ROLE ROW BY SUM(FTE). <== Writing the capacity itself scales the
    target by the role's FTE a SECOND time, which on these numbers would read 2.3x too high and
    look like a plausible stretch target rather than a bug."""
    rows = dict((lvl, v) for lvl, v in
                seed.derive_capacity_targets(ROLES, FTE, HOURS, REVENUE))
    assoc_fte = FTE[STEPHEN] + FTE[DAVID] + FTE[TESSA] + FTE[MARK]
    assert rows[seed.ROLE_ASSOCIATE] * assoc_fte < rows['Practice']
    assert rows[seed.ROLE_ASSOCIATE] < rows['Practice'] / assoc_fte * 1.01


def test_practice_and_roles_reconcile_exactly():
    """Nothing in the warehouse enforces this. When the two levels disagree, Home and a
    role-filtered page show different targets for the same metric and neither is arithmetically
    wrong -- which is how the live practice's hand-entered set drifted 30% apart."""
    rows = seed.derive_capacity_targets(ROLES, FTE, HOURS, REVENUE)
    practice = dict(rows)['Practice']
    role_fte = {}
    for pid, role in ROLES.items():
        role_fte[role] = role_fte.get(role, 0.0) + FTE[pid]
    rolled = sum(v * role_fte[lvl] for lvl, v in rows if lvl != 'Practice')
    assert abs(rolled - practice) < 1.0, (rolled, practice)


def test_the_leave_haircut_is_applied_once():
    """0.98, not 0.90. The forward diary already carries booked leave; the 10% figure was
    calibrated against raw diary span including lunch and blocks and double-counts here."""
    rows = dict(seed.derive_capacity_targets(
        {1: seed.ROLE_ASSOCIATE}, {1: 1.0}, {1: (1000.0, 1000.0)}, {1: 100000.0}))
    assert abs(rows['Practice'] - 98000.0) < 0.01


def test_capacity_with_no_fte_behind_it_inflates_the_per_fte_rate():
    """==> THE PER-FTE FIGURE IS capacity / role FTE. <== A locum carries hours and revenue but
    an FTE of zero, so their capacity lands in the numerator with nothing in the denominator.
    On matched rates that doubles the rate every real practitioner in the role is measured
    against -- and the DAX then multiplies it by THEIR FTE, so they each get twice the target."""
    roles = {1: seed.ROLE_HYGIENIST, 9: seed.ROLE_HYGIENIST}
    hours = {1: (1000.0, 1000.0), 9: (1000.0, 1000.0)}
    revenue = {1: 100000.0, 9: 100000.0}
    fte = {1: 1.0, 9: 0.0}
    with_locum = dict(seed.derive_capacity_targets(roles, fte, hours, revenue))
    without = dict(seed.derive_capacity_targets(roles, fte, hours, revenue, excluded={9}))
    assert with_locum[seed.ROLE_HYGIENIST] == 2 * without[seed.ROLE_HYGIENIST]
    assert without[seed.ROLE_HYGIENIST] == 98000.0


def test_the_live_locums_distortion_is_small_but_real():
    """Worth pinning the actual magnitude rather than assuming it. Maple's locum bills GBP 76/hr
    against a hygienist pool of GBP 78.7 and is rostered 10 forward hours against 149 behind, so
    the inflation is only ~0.1% -- the rate is near enough the pool's that the two effects
    nearly cancel. The rule is not kept for the size of this number; it is kept because the
    direction and size depend entirely on a locum we know nothing about."""
    roles = {1: seed.ROLE_HYGIENIST, 9: seed.ROLE_HYGIENIST}
    hours = {1: (3290.0, 3954.0), 9: (149.0, 10.0)}
    revenue = {1: 258919.0, 9: 11326.0}
    fte = {1: 2.12, 9: 0.0}
    with_locum = dict(seed.derive_capacity_targets(roles, fte, hours, revenue))
    without = dict(seed.derive_capacity_targets(roles, fte, hours, revenue, excluded={9}))
    assert with_locum[seed.ROLE_HYGIENIST] > without[seed.ROLE_HYGIENIST]
    assert with_locum[seed.ROLE_HYGIENIST] / without[seed.ROLE_HYGIENIST] < 1.01


def test_no_forward_hours_means_no_target_rather_than_a_zero():
    """A retiring practitioner rostered nothing forward contributes no capacity. A zero target
    reads as 100% achieved on every report; absent reads as absent."""
    rows = seed.derive_capacity_targets(
        {1: seed.ROLE_ASSOCIATE}, {1: 0.5}, {1: (1000.0, 0.0)}, {1: 50000.0})
    assert rows == []


def test_no_history_means_no_capacity_target():
    """A practice three months onto Dentally has no usable rate. The fixed and calculated
    classes still seed -- this must not take the whole target set down with it."""
    defs = [('private_revenue', 'currency', 'cumulative', True, True, '£450,000'),
            ('exam_ratio', 'percent', 'rate', False, True, '55%')]
    rows = seed.derive_targets(defs, ROLES, FTE, HOURS, {'private_revenue': REVENUE},
                               0, {}, have_rate=False)
    assert [r for r in rows if r[0] == 'private_revenue'] == []
    assert ('exam_ratio', 'Practice', 55.0) in rows


def test_nhs_targets_are_never_seeded():
    """They come from the Dentally contract via Silver.Practitioner_Contract_Targets."""
    defs = [('nhs_uda_completion_rate', 'percent', 'rate', False, True, '95%')]
    assert seed.derive_targets(defs, ROLES, FTE, HOURS, {}, 0, {}) == []


def test_plan_capitation_is_calculated_not_sampled():
    """GBP 35 x plan patients x 12 months. The sample of 120,000 is a generic figure and would
    be wrong for any practice that is not exactly average size."""
    defs = [('plan_capitation_revenue', 'currency', 'cumulative', True, True, '£120,000')]
    rows = seed.derive_targets(defs, ROLES, FTE, HOURS, {}, 1406, {})
    assert rows == [('plan_capitation_revenue', 'Practice', 35.0 * 1406 * 12)]


def test_a_percentage_uses_the_curated_sample_not_the_practices_own_actual():
    """==> PERCENTAGES ARE SIZE-INDEPENDENT. <== 'Exam ratio 55%' is as true for a two-chair
    practice as a ten-chair one, and seeding their own actual makes the target unmissable."""
    defs = [('exam_ratio', 'percent', 'rate', False, True, '55%')]
    rows = seed.derive_targets(defs, ROLES, FTE, HOURS, {}, 0, {'exam_ratio': (30.0, 100.0)})
    assert rows == [('exam_ratio', 'Practice', 55.0)]


def test_a_count_uses_the_practices_own_actual_not_the_sample():
    """The opposite case, and the reason the split exists: seeding 'active patients 6,000' into
    a practice with 1,800 gives them a target they can never hit."""
    defs = [('active_patients', 'count', 'rate', False, False, '6,000')]
    rows = seed.derive_targets(defs, ROLES, FTE, HOURS, {}, 0,
                               {'active_patients': (1800.0, 1.0)})
    assert rows == [('active_patients', 'Practice', 1800.0)]


def test_a_count_with_no_actual_falls_back_to_the_sample():
    defs = [('active_patients', 'count', 'rate', False, False, '6,000')]
    rows = seed.derive_targets(defs, ROLES, FTE, HOURS, {}, 0, {})
    assert rows == [('active_patients', 'Practice', 6000.0)]


def test_a_point_in_time_count_is_never_summed_across_the_window():
    """==> Numerator ON A SNAPSHOT METRIC IS THE LEVEL THAT DAY, RESTATED DAILY. <== A year's
    sum of active patients reads ~365x the real figure. If the windowed aggregate ever leaks
    into these, the seeded target lands three orders of magnitude out -- and a target nobody
    can approach looks like a broken report, not a wrong default."""
    defs = [('active_patients', 'count', 'point_in_time', False, False, '6,000')]
    rows = seed.derive_targets(defs, ROLES, FTE, HOURS, {}, 0,
                               {'active_patients': (2628000.0, 0.0)},     # 7,200 x 365
                               snapshots={'active_patients': (7200.0, 0.0)})
    assert rows == [('active_patients', 'Practice', 7200.0)]


def test_a_snapshot_with_no_reading_falls_back_to_the_sample():
    """A metric that has never computed must not seed a zero: on a 'higher is better' tile a
    zero target reads as 100% achieved for ever."""
    defs = [('overdue_recalls', 'count', 'point_in_time', False, False, '150')]
    rows = seed.derive_targets(defs, ROLES, FTE, HOURS, {}, 0, {}, snapshots={})
    assert rows == [('overdue_recalls', 'Practice', 150.0)]


def test_the_practices_own_size_beats_the_generic_sample():
    """The whole reason the split exists. 6,000 is the curated sample; this practice has 7,200
    and the seeded target has to be theirs."""
    defs = [('active_patients', 'count', 'point_in_time', False, False, '6,000')]
    rows = seed.derive_targets(defs, ROLES, FTE, HOURS, {}, 0, {},
                               snapshots={'active_patients': (7200.0, 0.0)})
    assert rows[0][2] == 7200.0 != seed.parse_sample('6,000')


# ── the write ─────────────────────────────────────────────────────────────────

class _Acur(object):
    """Answers the existence probes, records the inserts."""

    def __init__(self, existing=None):
        self.existing = existing or {}
        self.inserted = {}
        self._last = None

    def execute(self, sql, *args):
        for key in ('Practitioner_Role', 'Practitioner_Pay', 'Plan_Capitation_Rate', 'Targets'):
            if key in sql:
                self._last = key
        return self

    def fetchall(self):
        return self.existing.get(self._last, [])

    def executemany(self, sql, rows):
        for key in ('Practitioner_Role', 'Practitioner_Pay', 'Plan_Capitation_Rate', 'Targets'):
            if key in sql and 'INSERT' in sql:
                self.inserted.setdefault(key, []).extend(rows)


def _plan():
    p = seed.SeedPlan(12, dt.date(2026, 10, 27))
    p.fy = 2027
    p.roles = {1: seed.ROLE_ASSOCIATE, 2: seed.ROLE_HYGIENIST}
    p.fte = {1: 0.8, 2: 0.5}
    p.pct = {1: 50.0}
    p.plans = [(3, 'Denplan C', 35.0, 29.0)]
    p.targets = [('private_revenue', 'Practice', 100.0), ('exam_ratio', 'Practice', 55.0)]
    return p


def test_a_clean_tenant_gets_the_whole_plan():
    acur = _Acur()
    written = seed.apply_plan(acur, _plan())
    assert written == {'roles': 2, 'pay': 1, 'plans': 1, 'targets': 2}


def test_an_existing_value_is_never_overwritten():
    """==> THE CUSTOMER'S OWN EDITS WIN. <== A re-run must be safe. The live practice's 334
    target rows are all hand-set and a seeder that clobbered them would be unrecoverable."""
    acur = _Acur({'Practitioner_Role': [(1,)],
                  'Targets': [('exam_ratio', 'Practice')]})
    written = seed.apply_plan(acur, _plan())
    assert written['roles'] == 1                       # practitioner 2 only
    assert written['targets'] == 1                     # private_revenue only
    assert [r[1] for r in acur.inserted['Practitioner_Role']] == [2]
    assert [r[2] for r in acur.inserted['Targets']] == ['private_revenue']


def test_fte_is_written_to_practitioner_role_not_practitioner_pay():
    """==> BOTH INPUT TABLES CARRY AN FTE COLUMN AND ONLY ONE IS READ. <== Dim_Practitioners
    takes FTE from Practitioner_ROLE and defaults it to 1.0 when absent. Writing it to
    Practitioner_Pay is accepted, ignored, and leaves everyone on 1.0 -- which silently
    over-scales every role target and looks like the practice underperforming."""
    acur = _Acur()
    seed.apply_plan(acur, _plan())
    role_rows = acur.inserted['Practitioner_Role']
    assert [r[3] for r in role_rows] == [0.8, 0.5]
    assert len(acur.inserted['Practitioner_Pay'][0]) == 4     # no FTE column in the pay insert


def test_the_seed_is_attributed_to_itself():
    """Updated_By distinguishes a seeded value from one the customer chose, which is what any
    later 'these are still defaults' check has to key off."""
    acur = _Acur()
    seed.apply_plan(acur, _plan())
    for rows in acur.inserted.values():
        assert all(r[-1] == seed.SEED_ACTOR for r in rows)
