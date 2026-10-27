"""Derive a starting set of customer metadata from Dentally data alone.

==> THE REPORTS DO NOT WORK UNTIL THIS METADATA EXISTS. <== A new practice has no roles, no
FTE, no associate percentages, no plan rates and no targets -- none of which Dentally holds.
Without them the Day Book shows no targets, practitioner profitability cannot be computed and
plan capitation revenue reads zero, which is most of what a prospect looks at first.

This runs ONCE, after the Dentally ingest and first warehouse build, before reporting is
released to the customer. It aims at plausible, not accurate: a customer who sees working
reports and a banner saying the figures are estimates will correct the ones that matter to
them; a customer who sees blanks and a form to fill in will not.

READS the Fabric warehouse (Gold.*). WRITES the AppDB (Input.*) -- never the warehouse copy,
which Meta.usp_Sync_Input_From_AppDB full-refreshes on the next build.

    python onboarding_seed.py --tenant 12              # dry run, prints the plan
    python onboarding_seed.py --tenant 12 --apply      # writes it

==> DRY RUN IS THE DEFAULT AND --apply NEVER OVERWRITES. <== Every step skips a key that
already holds a value. A practice that has edited its own settings keeps them.

Design note: Onboarding Metadata Seeder.
"""
import argparse
import datetime as dt
import os
import sys

# ── the constants, all of them arguable, none of them hidden ─────────────────
# Each is a decision recorded in the design note rather than a tuned value.

LEAVE_FACTOR = 0.98
"""Leave still to be booked into the forward rota.

Measured on the live practice: the forward diary already carries 668 block hours against 768
trailing, so only ~2pp of leave is yet to appear. ==> THIS IS NOT 10%. <== An earlier 10% was
calibrated against raw diary span INCLUDING lunch and blocks; on the Worked_Hours basis below
most of that is already subtracted, and applying 10% again double-counts it."""

SPECIALIST_LIST_FRACTION = 0.10
"""A dentist holding less than this share of the MEDIAN dentist's list is a session worker.

Relative to the practice's own median, not a flat percentage, so it holds in a two-dentist
practice and a twenty-dentist one alike. The live practice separates 20x either side of it --
the smallest list-holder owns 783 patients and the largest session worker owns 40."""

REGULAR_WEEK_FRACTION = 0.75
FTE_HOURS_PER_WEEK = 37.5
FTE_WINDOW_WEEKS = 26          # 3 months back + 3 forward

ASSOCIATE_PCT_DEFAULT = 50.0   # industry going rate; principals none, hygienists blank

PLAN_MONTHLY_DEFAULT = 35.0
PLAN_CROSS_CHARGE_DEFAULT = 29.0
PLAN_FREE_EXAM_PCT = 95.0
PLAN_MIN_EXAMS = 10
"""Low on purpose. A children's plan carried 16 exams in a year at the live practice and is a
real capitation plan; a threshold of 20 would have dropped it."""

RATE_WINDOW_DAYS = 365
RATE_MIN_DAYS = 90
"""Three months is the floor for a usable rate. Below it no capacity target is written at all
-- the fixed and calculated classes still seed."""

CLINICAL_ROLES = ('dentist', 'hygienist', 'orthodontist', 'specialist', 'therapist')
CAPACITY_METRICS = ('private_revenue', 'total_revenue')
CAPITATION_METRIC = 'plan_capitation_revenue'

BLOCK_REASONS = ('NOT WORKING', 'Not working', 'Lunch', 'Annual Leave', 'Bank Holiday',
                 'Training Course', 'Meeting', 'Medical appointment', 'Other')

ROLE_PRINCIPAL = 'Principal'
ROLE_ASSOCIATE = 'Associate'
ROLE_SPECIALIST = 'Associate Specialist'
ROLE_HYGIENIST = 'Hygienist'

SEED_ACTOR = 'onboarding-seed'


# ── Worked_Hours: the product's own basis, not raw diary span ────────────────
# Gold.usp_Load_Aggregate_Site_Patient_Practitioner_Daily defines clinical hours as
# Available_Clinical_Mins (scheduled time AFTER breaks) minus on-day block appointments, floored
# at 0. ==> A TARGET BUILT ON ANY OTHER BASIS IS COMPARED AGAINST AN ACTUAL THAT IS NOT IT. <==
# Raw diary span runs ~11% higher on the live practice, which silently inflates every rate.
# The forward half has to be computed here because Fact_Metric_Actuals only holds history.

# ==> THE CREATING BATCH MUST NOT BE PARAMETERISED. <== pyodbc sends a parameterised statement
# through sp_executesql, and a temp table created inside that call is scoped to it and dropped
# the moment it returns -- the next execute() then fails with "Invalid object name '#seed_day'".
# Reading an outer-scope temp table from inside sp_executesql is fine, so every query BELOW is
# parameterised normally; only this one inlines its values. Both are ours (an int from argparse
# and module constants), never user input, and the int is cast rather than trusted.

_SCRATCH_SQL = """
DROP TABLE IF EXISTS #seed_day;
SELECT f.fk_Practitioner AS fkp, f.fk_Date_Day AS fkd,
       CASE WHEN SUM(f.Available_Clinical_Mins) - MAX(ISNULL(b.blk, 0)) < 0 THEN 0
            ELSE SUM(f.Available_Clinical_Mins) - MAX(ISNULL(b.blk, 0)) END / 60.0 AS wh
INTO   #seed_day
FROM   Gold.Fact_Practitioner_Diaries f
LEFT JOIN (SELECT a.fk_Practitioner, a.fk_Date_Start AS fk_Date,
                  SUM(ISNULL(a.Duration_Mins, 0)) AS blk
           FROM   Gold.Fact_Appointments a
           WHERE  a.Tenant_ID = {tenant} AND a.Is_Cancelled = 0
              AND (a.fk_Patient IS NULL OR a.fk_Patient <= 0)
              AND a.Reason IN ({reasons})
           GROUP BY a.fk_Practitioner, a.fk_Date_Start) b
       ON b.fk_Practitioner = f.fk_Practitioner AND b.fk_Date = f.fk_Date_Day
WHERE  f.Tenant_ID = {tenant} AND ISNULL(f.Is_Dummy, 0) = 0
GROUP BY f.fk_Practitioner, f.fk_Date_Day;
"""


def build_hours_scratch(cur, tenant_id):
    """Materialise #seed_day for this connection.

    Temp table, not a CTE: a re-referenced CTE re-evaluates its source in Fabric and loses
    statistics, and #seed_day is read three times (FTE weeks, trailing hours, forward hours).
    """
    reasons = ','.join("'%s'" % r.replace("'", "''") for r in BLOCK_REASONS)
    cur.execute(_SCRATCH_SQL.format(tenant=int(tenant_id), reasons=reasons))


# ── Step 1: roles ────────────────────────────────────────────────────────────

def fetch_role_inputs(cur, tenant_id):
    """(practitioner_id, pk, full_name, dentally_role, patients_owned) for active clinicians."""
    cur.execute(
        "SELECT p.Practitioner_ID, p.pk_Practitioner, p.Full_Name, LOWER(ISNULL(p.Role,'')), "
        "       ISNULL(o.n, 0) "
        "FROM   Gold.Dim_Practitioners p "
        "LEFT JOIN (SELECT fk_Current_Dentist AS fkp, COUNT(*) AS n "
        "           FROM   Gold.Dim_Patients "
        "           WHERE  Tenant_ID = ? AND ISNULL(Active,1) = 1 "
        "              AND fk_Current_Dentist IS NOT NULL "
        "           GROUP BY fk_Current_Dentist) o ON o.fkp = p.pk_Practitioner "
        "WHERE  p.Tenant_ID = ? AND p.Active = 1 AND p.pk_Practitioner > 0 "
        "   AND LOWER(ISNULL(p.Role,'')) IN (%s)" % ','.join('?' * len(CLINICAL_ROLES)),
        (tenant_id, tenant_id) + CLINICAL_ROLES)
    return [tuple(r) for r in cur.fetchall()]


def find_principal(cur, tenant_id):
    """The single provisioned account at onboarding identifies the principal.

    ==> IT IS THE APP'S OWN ACCOUNT, NOT A DENTALLY SIGNAL. <== Dentally access is not set up at
    onboarding, so permission level tells us nothing (and on the live practice every account was
    bulk-created at the migration date, so account age tells us nothing either).

    ==> MATCH ON EMAIL, NOT ON Practitioner_Full_Name. <== Audit.usp_Provision_Tenant inserts the
    signup with Practitioner_Full_Name = NULL and User_UPN = @Principal_Email, and it runs at
    STEP 0 of onboarding -- BEFORE any Dentally data exists, so it could not name a practitioner
    even in principle. A lookup keyed on that column finds nobody on the one run that matters.
    The full name is still accepted as a fallback, for a practice where an admin has since linked
    accounts by hand.

    Security.Application_Users keys on Client_ID, not Tenant_ID -- one client can own several
    practices -- so the tenant resolves through Audit.Tenants.

    Returns a practitioner_id, or None. ==> None IS A LEGITIMATE ANSWER, NOT A FAILURE. <== The
    signup may be the office manager rather than a dentist, or the practice may already carry
    several accounts and nothing says which came first. A practice with no principal has every
    dentist default to Associate, which the owner accepted as close enough. The live practice
    returns None for the second reason: six accounts, three of them matching a dentist.
    """
    cur.execute(
        "SELECT u.User_UPN, u.Practitioner_Full_Name FROM Security.Application_Users u "
        "JOIN   Audit.Tenants t ON t.Client_ID = u.Client_ID "
        "WHERE  t.Tenant_ID = ?", tenant_id)
    accounts = [tuple(r) for r in cur.fetchall()]
    if len(accounts) != 1:
        return None
    upn, full_name = accounts[0]

    cur.execute(
        "SELECT Practitioner_ID FROM Gold.Dim_Practitioners "
        "WHERE  Tenant_ID = ? AND Active = 1 AND LOWER(ISNULL(Role,'')) = 'dentist' "
        "   AND (LOWER(LTRIM(RTRIM(ISNULL(Email,'')))) = LOWER(LTRIM(RTRIM(ISNULL(?, '')))) "
        "    OR  LOWER(LTRIM(RTRIM(ISNULL(Full_Name,'')))) = LOWER(LTRIM(RTRIM(ISNULL(?, ''))))) ",
        (tenant_id, upn or '', full_name or ''))
    rows = cur.fetchall()
    return int(rows[0][0]) if len(rows) == 1 else None


def derive_roles(rows, principal_id=None):
    """Applied in order, first match wins. `rows` as fetch_role_inputs returns them.

    Specialisms are not distinguished -- implantologist, orthodontist and specialist all seed as
    Associate Specialist. Work-type detection would need Treatment_Category_Map, which is empty,
    so all 336 treatment types echo their raw text.
    """
    dentist_lists = sorted(owned for _, _, _, role, owned in rows if role == 'dentist')
    median_list = _median(dentist_lists) if dentist_lists else 0.0
    threshold = median_list * SPECIALIST_LIST_FRACTION

    roles = {}
    for pid, _pk, name, role, owned in rows:
        if role == 'hygienist':
            roles[pid] = ROLE_HYGIENIST
        elif principal_id is not None and pid == principal_id:
            roles[pid] = ROLE_PRINCIPAL
        elif owned < threshold:
            roles[pid] = ROLE_SPECIALIST
        else:
            roles[pid] = ROLE_ASSOCIATE
    return roles


def is_locum(full_name):
    """A locum is a succession of different people, so a target for one is meaningless.

    Name match is the only signal Dentally offers. It stays out of targeting entirely -- both
    halves of the derivation -- so the Hygienist per-FTE rate is not inflated by capacity that
    carries no FTE against it."""
    return 'locum' in (full_name or '').lower()


# ── Step 2: FTE ──────────────────────────────────────────────────────────────

def fetch_weekly_hours(cur, tenant_id, window_start, window_end):
    """(practitioner_id, week_index, worked_hours) over the FTE window, non-zero weeks only.

    The week index is computed in a derived table rather than repeated in SELECT and GROUP BY:
    Fabric will not match two occurrences of a parameterised DATEDIFF as the same expression.
    """
    cur.execute(
        "SELECT x.pid, x.wk, SUM(x.wh) "
        "FROM ( SELECT p.Practitioner_ID AS pid, "
        "              DATEDIFF(WEEK, ?, dd.Full_Date) AS wk, d.wh AS wh "
        "       FROM   #seed_day d "
        "       JOIN   Gold.Dim_Date dd ON dd.pk_Date = d.fkd "
        "       JOIN   Gold.Dim_Practitioners p ON p.pk_Practitioner = d.fkp "
        "       WHERE  p.Tenant_ID = ? AND dd.Full_Date >= ? AND dd.Full_Date < ? ) x "
        "GROUP BY x.pid, x.wk HAVING SUM(x.wh) > 0",
        (window_start, tenant_id, window_start, window_end))
    return [(int(r[0]), int(r[1]), float(r[2])) for r in cur.fetchall()]


def derive_fte(weekly_rows, window_weeks=FTE_WINDOW_WEEKS):
    """Two methods, chosen by how regularly the person works.

    Regular (worked 75%+ of the window's weeks) -- median NON-ZERO week / 37.5. The median is
    over weeks actually worked, so annual leave does not drag a full-timer down.

    ==> THAT SAME PROPERTY BREAKS IT FOR SPORADIC WORKERS. <== Someone in one week of three has
    a median measuring the week they DO work, which overstated two session dentists by roughly
    double on the live practice. Those get total hours / (37.5 x window weeks) instead.
    """
    by_prac = {}
    for pid, _wk, hrs in weekly_rows:
        by_prac.setdefault(pid, []).append(hrs)

    fte = {}
    for pid, hours in by_prac.items():
        if len(hours) >= REGULAR_WEEK_FRACTION * window_weeks:
            value = _median(sorted(hours)) / FTE_HOURS_PER_WEEK
        else:
            value = sum(hours) / (FTE_HOURS_PER_WEEK * window_weeks)
        fte[pid] = round(value, 2)
    return fte


def _median(ordered):
    """Median of an already-sorted list. Empty -> 0.0."""
    n = len(ordered)
    if n == 0:
        return 0.0
    mid = n // 2
    if n % 2:
        return float(ordered[mid])
    return (float(ordered[mid - 1]) + float(ordered[mid])) / 2.0


# ── Step 3: associate percentage ─────────────────────────────────────────────

def derive_associate_pct(roles):
    """Customer-entered data with NO Dentally source whatsoever -- this is a pure default.

    Principals take none because they take the profit rather than a share. Hygienists are blank
    because they are salaried. The live practice is an exception on both counts, setting a rate
    for its two principals and one outlying associate, but that is a two-partner arrangement for
    splitting a pooled profit and a single-principal practice would not do it at all.

    Returns only the practitioners that get a value; absent = write nothing.
    """
    return {pid: ASSOCIATE_PCT_DEFAULT
            for pid, role in roles.items()
            if role in (ROLE_ASSOCIATE, ROLE_SPECIALIST)}


# ── Step 4: plan rates ───────────────────────────────────────────────────────

def fetch_plan_signal(cur, tenant_id, window_start, window_end):
    """(payment_plan_id, name, exams, free_exams) -- the capitation signal, per plan."""
    cur.execute(
        "SELECT p.Payment_Plan_ID, p.Payment_Plan_Name, SUM(a.Exam_Count), "
        "       SUM(CASE WHEN ISNULL(a.Private_Revenue,0) = 0 THEN a.Exam_Count ELSE 0 END) "
        "FROM   Gold.Aggregate_Site_Patient_Practitioner_Daily a "
        "JOIN   Gold.Dim_Date dd ON dd.pk_Date = a.fk_Date "
        "JOIN   Gold.Dim_Patients pt ON pt.pk_Patient = a.fk_Patient "
        "                           AND pt.Tenant_ID = a.Tenant_ID "
        "JOIN   Gold.Dim_Payment_Plans p ON p.Tenant_ID = a.Tenant_ID "
        "                               AND p.Payment_Plan_ID = pt.Payment_Plan_ID "
        "WHERE  a.Tenant_ID = ? AND a.Exam_Count > 0 "
        "   AND dd.Full_Date >= ? AND dd.Full_Date < ? "
        "GROUP BY p.Payment_Plan_ID, p.Payment_Plan_Name",
        (tenant_id, window_start, window_end))
    return [(int(r[0]), r[1], int(r[2] or 0), int(r[3] or 0)) for r in cur.fetchall()]


def derive_plans(signal_rows):
    """Plan patients get their examinations included, so a capitation plan shows almost every
    exam charged at zero. Plan NAMES cannot be used -- "Denplan C" and the rest are free text.

    ==> NHS IS THE FALSE POSITIVE TO GUARD AGAINST. <== NHS exams are free to the patient too.
    On the live practice the NHS plan ran 85.3% free against 95.6-100% for the eight real
    capitation plans, so the threshold separates them -- but only by ten points, and
    NHS_Revenue is not populated on the daily aggregate so it cannot discriminate instead.
    The name guard is therefore belt and braces, not redundancy.

    Returns [(plan_id, name, monthly, cross_charge)]. Every plan gets the SAME rate: guessing a
    per-tier structure the practice has not told us produces a wrong specific number, which is
    harder to spot than an obviously uniform one.
    """
    plans = []
    for plan_id, name, exams, free in sorted(signal_rows):
        if exams < PLAN_MIN_EXAMS:
            continue
        if _looks_nhs(name):
            continue
        if 100.0 * free / exams >= PLAN_FREE_EXAM_PCT:
            plans.append((plan_id, name, PLAN_MONTHLY_DEFAULT, PLAN_CROSS_CHARGE_DEFAULT))
    return plans


def _looks_nhs(name):
    """Whole-word NHS. The warehouse collation is case-sensitive so the fold has to be explicit."""
    return 'nhs' in (name or '').lower().replace('-', ' ').split()


# ── Step 5: targets ──────────────────────────────────────────────────────────

def fetch_metric_definitions(cur):
    """The target set is Config.Metric_Definitions, NOT a list hard-coded here.

    Has_Target is NULL for every row and the grid reads ISNULL(Has_Target,1)=1, so NULL means
    yes. Sample_Value is the curated industry number the Settings screen already shows as
    "e.g. 55%" -- the magic numbers are written down, and this reads them rather than inventing
    a second set that can drift from the UI."""
    cur.execute(
        "SELECT Metric_Key, Format_Type, Target_Type, ISNULL(FTE_Scaled,0), "
        "       ISNULL(Supports_Practitioner,0), Sample_Value "
        "FROM   Config.Metric_Definitions "
        "WHERE  Is_Active = 1 AND ISNULL(Has_Target, 1) = 1")
    return [(r[0], r[1], r[2], bool(r[3]), bool(r[4]), r[5]) for r in cur.fetchall()]


def parse_sample(sample):
    """"£600,000" -> 600000.0, "55%" -> 55.0, "1,200" -> 1200.0. Unparseable -> None.

    Percentages store as whole numbers: the DAX divides by 100 (tRate100), and the live
    practice's deposit ratio is stored as 4 for 4%."""
    if sample is None:
        return None
    cleaned = ''.join(c for c in str(sample) if c.isdigit() or c in '.-')
    if not cleaned or cleaned in ('.', '-', '-.'):
        return None
    try:
        return float(cleaned)
    except ValueError:
        return None


def fetch_capacity_inputs(cur, tenant_id, hist_start, asof, fwd_end):
    """Per practitioner: trailing Worked_Hours, forward Worked_Hours, and trailing revenue."""
    cur.execute(
        "SELECT p.Practitioner_ID, "
        "       SUM(CASE WHEN dd.Full_Date <  ? THEN d.wh END), "
        "       SUM(CASE WHEN dd.Full_Date >= ? THEN d.wh END) "
        "FROM   #seed_day d "
        "JOIN   Gold.Dim_Date dd ON dd.pk_Date = d.fkd "
        "JOIN   Gold.Dim_Practitioners p ON p.pk_Practitioner = d.fkp "
        "WHERE  p.Tenant_ID = ? AND dd.Full_Date >= ? AND dd.Full_Date < ? "
        "GROUP BY p.Practitioner_ID",
        (asof, asof, tenant_id, hist_start, fwd_end))
    hours = {int(r[0]): (float(r[1] or 0), float(r[2] or 0)) for r in cur.fetchall()}

    cur.execute(
        "SELECT p.Practitioner_ID, a.Metric, SUM(a.Numerator) "
        "FROM   Gold.Fact_Metric_Actuals a "
        "JOIN   Gold.Dim_Date dd ON dd.pk_Date = a.fk_Date "
        "JOIN   Gold.Dim_Practitioners p ON p.pk_Practitioner = a.fk_Practitioner "
        "WHERE  a.Tenant_ID = ? AND a.fk_Practitioner <> -1 "
        "   AND a.Metric IN (%s) AND dd.Full_Date >= ? AND dd.Full_Date < ? "
        "GROUP BY p.Practitioner_ID, a.Metric" % ','.join('?' * len(CAPACITY_METRICS)),
        (tenant_id,) + CAPACITY_METRICS + (hist_start, asof))
    revenue = {}
    for pid, metric, total in cur.fetchall():
        revenue.setdefault(metric, {})[int(pid)] = float(total or 0)
    return hours, revenue


def derive_capacity_targets(roles, fte, hours, revenue, excluded=()):
    """forward Worked_Hours x 0.98 x (historical revenue / historical Worked_Hours), per role.

    ==> THE ROLE VALUE IS STORED PER-FTE, NOT AS THE CAPACITY. <== Input.Targets holds one row
    per (FY, Metric, Target_Level) and the DAX multiplies a role row by SUM(FTE) in context, so
    the seeder has to divide. Writing the capacity itself multiplies the target by the role's
    FTE a second time.

    Practice is the SUM of the role capacities, which is what makes the two levels reconcile --
    nothing in the warehouse enforces that they agree, and the live practice's hand-entered set
    is 30% out between its own levels.

    Returns [(target_level, value)], Practice first, or [] if there is no usable rate.
    """
    per_role = {}
    for pid, role in roles.items():
        if pid in excluded:
            continue
        hist_wh, fwd_wh = hours.get(pid, (0.0, 0.0))
        if fwd_wh <= 0:
            continue
        agg = per_role.setdefault(role, {'hist': 0.0, 'fwd': 0.0, 'rev': 0.0, 'fte': 0.0})
        agg['hist'] += hist_wh
        agg['fwd'] += fwd_wh
        agg['rev'] += revenue.get(pid, 0.0)
        agg['fte'] += fte.get(pid, 0.0)

    out, practice_total = [], 0.0
    for role, agg in sorted(per_role.items()):
        if agg['hist'] <= 0 or agg['fte'] <= 0:
            continue
        capacity = agg['fwd'] * LEAVE_FACTOR * (agg['rev'] / agg['hist'])
        if capacity <= 0:
            continue
        practice_total += capacity
        out.append((role, round(capacity / agg['fte'], 2)))

    if practice_total <= 0:
        return []
    return [('Practice', round(practice_total, 2))] + out


def fetch_plan_patient_count(cur, tenant_id, plan_ids):
    """Active patients on the identified capitation plans."""
    if not plan_ids:
        return 0
    cur.execute(
        "SELECT COUNT(*) FROM Gold.Dim_Patients "
        "WHERE Tenant_ID = ? AND ISNULL(Active,1) = 1 AND Payment_Plan_ID IN (%s)"
        % ','.join('?' * len(plan_ids)), (tenant_id,) + tuple(plan_ids))
    row = cur.fetchone()
    return int(row[0]) if row else 0


def fetch_practice_actuals(cur, tenant_id, hist_start, asof):
    """Trailing practice-level actuals, keyed by metric, for the size-dependent targets.

    An industry sample is the right default for a PERCENTAGE -- those are size-independent, and
    "exam ratio 55%" is as true for a two-chair practice as a ten-chair one. It is the wrong
    default for a COUNT or a VALUE: seeding "active patients 6,000" into a practice with 1,800
    gives them a target they can never hit and a report that looks broken.

    Returns {metric: (numerator, denominator)} summed over the window.
    """
    cur.execute(
        "SELECT a.Metric, SUM(a.Numerator), SUM(a.Denominator) "
        "FROM   Gold.Fact_Metric_Actuals a "
        "JOIN   Gold.Dim_Date dd ON dd.pk_Date = a.fk_Date "
        "WHERE  a.Tenant_ID = ? AND a.fk_Practitioner = -1 "
        "   AND dd.Full_Date >= ? AND dd.Full_Date < ? "
        "GROUP BY a.Metric", (tenant_id, hist_start, asof))
    return {r[0]: (float(r[1] or 0), float(r[2] or 0)) for r in cur.fetchall()}


def fetch_practice_snapshots(cur, tenant_id, hist_start, asof):
    """The LATEST value of each point_in_time metric, not a sum of them.

    ==> SUMMING A SNAPSHOT READS ~365x THE REAL LEVEL. <== Numerator on a point_in_time metric
    is the level ON that day, restated daily. Active patients summed over a year would seed a
    target in the millions, which is why these are fetched separately rather than folded into
    the aggregate above.

    Returns {metric: (numerator, denominator)} on each metric's own most recent day -- metrics
    stop on different dates, so one shared MAX would silently drop the others.
    """
    cur.execute(
        "SELECT x.Metric, x.Numerator, x.Denominator FROM ( "
        "  SELECT a.Metric, a.Numerator, a.Denominator, "
        "         ROW_NUMBER() OVER (PARTITION BY a.Metric ORDER BY dd.Full_Date DESC) AS rn "
        "  FROM   Gold.Fact_Metric_Actuals a "
        "  JOIN   Gold.Dim_Date dd ON dd.pk_Date = a.fk_Date "
        "  WHERE  a.Tenant_ID = ? AND a.fk_Practitioner = -1 "
        "     AND dd.Full_Date >= ? AND dd.Full_Date < ? AND a.Numerator IS NOT NULL ) x "
        "WHERE x.rn = 1", (tenant_id, hist_start, asof))
    return {r[0]: (float(r[1] or 0), float(r[2] or 0)) for r in cur.fetchall()}


def derive_targets(definitions, roles, fte, hours, revenue, plan_patients,
                   practice_actuals, snapshots=None, excluded=(), have_rate=True):
    """Four classes of target row, in priority order.

    1. Capacity-derived -- the two revenue metrics, Practice and per role
    2. Calculated       -- plan capitation = GBP 35 x plan patients x 12 months
    3. Fixed            -- every percentage, from the curated Sample_Value
    4. Measured         -- remaining counts and values, from the practice's own trailing actual

    NHS targets are not seeded at all: they come from the Dentally contract via
    Silver.Practitioner_Contract_Targets and need nothing from us.
    """
    out = []
    for key, fmt, target_type, _xfte, _by_role, sample in sorted(definitions):
        if key.startswith('nhs_'):
            continue

        if key in CAPACITY_METRICS:
            if have_rate:
                for level, value in derive_capacity_targets(
                        roles, fte, hours, revenue.get(key, {}), excluded):
                    out.append((key, level, value))
            continue

        if key == CAPITATION_METRIC:
            if plan_patients:
                out.append((key, 'Practice',
                            round(PLAN_MONTHLY_DEFAULT * plan_patients * 12, 2)))
            continue

        if fmt == 'percent':
            value = parse_sample(sample)
            if value is not None:
                out.append((key, 'Practice', value))
            continue

        value = _actual_for(key, target_type, practice_actuals, snapshots or {})
        if value is None:
            value = parse_sample(sample)
        if value is not None:
            out.append((key, 'Practice', round(value, 2)))
    return out


def _actual_for(key, target_type, actuals, snapshots):
    """The practice's own trailing figure, on the metric's own target type.

    cumulative    -- summed across the window (a year's worth)
    rate          -- numerator over denominator
    point_in_time -- the LATEST day's level, never the sum (see fetch_practice_snapshots)
    """
    if target_type == 'point_in_time':
        if key not in snapshots:
            return None
        num, den = snapshots[key]
        return (num / den if den else None) if den else (num or None)
    if key not in actuals:
        return None
    num, den = actuals[key]
    if target_type == 'rate':
        return num / den if den else None
    return num if num else None


# ── the plan, and writing it ─────────────────────────────────────────────────

class SeedPlan(object):
    """What the seeder would write, and what it is leaving alone."""

    def __init__(self, tenant_id, asof):
        self.tenant_id = tenant_id
        self.asof = asof
        self.roles = {}
        self.fte = {}
        self.pct = {}
        self.plans = []
        self.targets = []
        self.names = {}
        self.skipped = []
        self.notes = []

    def note(self, text):
        self.notes.append(text)

    def skip(self, text):
        self.skipped.append(text)


def build_plan(cur, tenant_id, asof=None, fy=None, principal_id=None):
    """Derive everything. Reads only -- nothing is written here."""
    asof = asof or dt.date.today()
    fy = fy or _default_fy(asof)
    plan = SeedPlan(tenant_id, asof)

    hist_start = asof - dt.timedelta(days=RATE_WINDOW_DAYS)
    fwd_end = asof + dt.timedelta(days=RATE_WINDOW_DAYS)
    fte_start = asof - dt.timedelta(days=91)
    fte_end = asof + dt.timedelta(days=91)

    build_hours_scratch(cur, tenant_id)

    rows = fetch_role_inputs(cur, tenant_id)
    if not rows:
        plan.note('No active clinical practitioners -- nothing to seed.')
        return plan
    plan.names = {pid: name for pid, _pk, name, _r, _o in rows}
    locums = {pid for pid, _pk, name, _r, _o in rows if is_locum(name)}

    if principal_id is None:
        principal_id = find_principal(cur, tenant_id)
    if principal_id is None:
        plan.note('No principal identified -- every dentist defaults to Associate.')
    else:
        plan.note('Principal: %s.' % plan.names.get(principal_id, principal_id))

    plan.roles = derive_roles(rows, principal_id)
    plan.fte = derive_fte(fetch_weekly_hours(cur, tenant_id, fte_start, fte_end))
    for pid in locums:
        plan.fte[pid] = 0.0
        plan.note('%s excluded from targeting (locum).' % plan.names.get(pid))
    for pid in plan.roles:
        plan.fte.setdefault(pid, 0.0)
    plan.pct = {pid: v for pid, v in derive_associate_pct(plan.roles).items()
                if pid not in locums}

    plan.plans = derive_plans(fetch_plan_signal(cur, tenant_id, hist_start, asof))
    plan_patients = fetch_plan_patient_count(
        cur, tenant_id, [p[0] for p in plan.plans])
    plan.note('%d capitation plan(s) identified, %d plan patients.'
              % (len(plan.plans), plan_patients))

    hours, revenue = fetch_capacity_inputs(cur, tenant_id, hist_start, asof, fwd_end)
    have_rate = _history_days(cur, tenant_id, asof) >= RATE_MIN_DAYS
    if not have_rate:
        plan.note('Under %d days of revenue history -- no capacity targets written.'
                  % RATE_MIN_DAYS)

    plan.targets = derive_targets(
        fetch_metric_definitions(cur), plan.roles, plan.fte, hours, revenue,
        plan_patients, fetch_practice_actuals(cur, tenant_id, hist_start, asof),
        snapshots=fetch_practice_snapshots(cur, tenant_id, hist_start, asof),
        excluded=locums, have_rate=have_rate)
    plan.fy = fy
    return plan


def _history_days(cur, tenant_id, asof):
    cur.execute(
        "SELECT DATEDIFF(DAY, MIN(dd.Full_Date), ?) FROM Gold.Fact_Metric_Actuals a "
        "JOIN Gold.Dim_Date dd ON dd.pk_Date = a.fk_Date "
        "WHERE a.Tenant_ID = ? AND a.Metric = 'private_revenue' AND a.Numerator > 0",
        (asof, tenant_id))
    row = cur.fetchone()
    return int(row[0]) if row and row[0] is not None else 0


def _default_fy(asof):
    """FY END year, as the app writes it (2027 = FY 2026-27)."""
    return asof.year + 1 if asof.month >= 4 else asof.year


def apply_plan(acur, plan, actor=SEED_ACTOR, phase='all'):
    """Write to the AppDB.

    ==> THE TWO PHASES EXIST BECAUSE OF A CIRCULARITY IN THE ONBOARDING RUN. <== The seeded plan
    rates feed Fact_Revenue's capitation half, which feeds Fact_Metric_Actuals, which is where
    the revenue TARGETS get their rate from. Writing both at once derives total_revenue from
    actuals that do not yet carry any capitation, and seeds it low.

      phase='rates'   -- roles, FTE, associate percentages, plan rates
      phase='targets' -- targets only, after the Gold re-run has picked the rates up
      phase='all'     -- both, correct only when capitation is already computed

    Orchestrate_Onboarding's STEP 6 is the re-run that sits between them. ==> NEVER OVERWRITES. <== Each step reads what is already there and
    writes only the keys that are absent, so a re-run after the customer has edited their own
    settings leaves those edits alone.

    The AppDB connection must be autocommit -- without it a write rolls back silently while the
    caller reports success."""
    written = {'roles': 0, 'pay': 0, 'plans': 0, 'targets': 0}
    t = plan.tenant_id
    do_rates = phase in ('all', 'rates')
    do_targets = phase in ('all', 'targets')

    if not do_rates:
        return _apply_targets(acur, plan, actor, written) if do_targets else written

    acur.execute("SELECT Practitioner_ID FROM Input.Practitioner_Role WHERE Tenant_ID = ?", t)
    have = {int(r[0]) for r in acur.fetchall()}
    rows = [(t, pid, role, plan.fte.get(pid, 0.0), actor)
            for pid, role in sorted(plan.roles.items()) if pid not in have]
    if rows:
        acur.executemany(
            "INSERT INTO Input.Practitioner_Role "
            "(Tenant_ID, Practitioner_ID, Custom_Role, FTE, Updated_At, Updated_By) "
            "VALUES (?, ?, ?, ?, SYSUTCDATETIME(), ?)", rows)
        written['roles'] = len(rows)

    acur.execute("SELECT Practitioner_ID FROM Input.Practitioner_Pay WHERE Tenant_ID = ?", t)
    have = {int(r[0]) for r in acur.fetchall()}
    rows = [(t, pid, pct, actor) for pid, pct in sorted(plan.pct.items()) if pid not in have]
    if rows:
        acur.executemany(
            "INSERT INTO Input.Practitioner_Pay "
            "(Tenant_ID, Practitioner_ID, Associate_Pct, Updated_At, Updated_By) "
            "VALUES (?, ?, ?, SYSUTCDATETIME(), ?)", rows)
        written['pay'] = len(rows)

    acur.execute("SELECT Payment_Plan_ID FROM Input.Plan_Capitation_Rate WHERE Tenant_ID = ?", t)
    have = {int(r[0]) for r in acur.fetchall()}
    rows = [(t, pid, plan.asof, monthly, 0, cross, actor)
            for pid, _name, monthly, cross in plan.plans if pid not in have]
    if rows:
        acur.executemany(
            "INSERT INTO Input.Plan_Capitation_Rate "
            "(Tenant_ID, Payment_Plan_ID, Effective_From_Date, Monthly_Value, Is_Default, "
            " Hygienist_Visit_Value, Updated_At, Updated_By) "
            "VALUES (?, ?, ?, ?, ?, ?, SYSUTCDATETIME(), ?)", rows)
        written['plans'] = len(rows)

    if not do_targets:
        return written
    return _apply_targets(acur, plan, actor, written)


def _apply_targets(acur, plan, actor, written):
    t = plan.tenant_id
    acur.execute("SELECT Metric, Target_Level FROM Input.Targets WHERE Tenant_ID = ? AND FY = ?",
                 (t, plan.fy))
    have = {(r[0], r[1]) for r in acur.fetchall()}
    rows = [(t, plan.fy, metric, level, value, actor)
            for metric, level, value in plan.targets if (metric, level) not in have]
    if rows:
        acur.executemany(
            "INSERT INTO Input.Targets "
            "(Tenant_ID, FY, Metric, Target_Level, Target_Value, Updated_At, Updated_By) "
            "VALUES (?, ?, ?, ?, ?, SYSUTCDATETIME(), ?)", rows)
        written['targets'] = len(rows)

    return written


def format_plan(plan):
    """What the dry run prints."""
    out = ['', 'ONBOARDING SEED -- tenant %d, as at %s, FY %s'
           % (plan.tenant_id, plan.asof, getattr(plan, 'fy', '?')), '=' * 72]
    for n in plan.notes:
        out.append('  * ' + n)

    out += ['', 'ROLES AND FTE', '-' * 72,
            '  %-24s %-22s %6s %8s' % ('Practitioner', 'Role', 'FTE', 'Assoc %')]
    for pid in sorted(plan.roles, key=lambda p: (plan.roles[p], plan.names.get(p, ''))):
        pct = plan.pct.get(pid)
        out.append('  %-24s %-22s %6.2f %8s'
                   % (plan.names.get(pid, pid)[:24], plan.roles[pid],
                      plan.fte.get(pid, 0.0), '%.0f' % pct if pct is not None else '-'))

    out += ['', 'CAPITATION PLANS', '-' * 72]
    if not plan.plans:
        out.append('  (none identified)')
    for _pid, name, monthly, cross in plan.plans:
        out.append('  %-30s %8.2f /month   cross-charge %6.2f' % (name[:30], monthly, cross))

    out += ['', 'TARGETS (FY %s)' % getattr(plan, 'fy', '?'), '-' * 72]
    for metric, level, value in plan.targets:
        out.append('  %-32s %-22s %14s' % (metric, level, '{:,.2f}'.format(value)))

    # ==> THE TWO LEVELS MUST AGREE. <== Nothing in the warehouse enforces it, and when they
    # disagree Home and a role-filtered page show different targets for the same metric.
    out += ['', 'RECONCILIATION', '-' * 72]
    role_fte = {}
    for pid, role in plan.roles.items():
        role_fte[role] = role_fte.get(role, 0.0) + plan.fte.get(pid, 0.0)
    practice = {m: v for m, l, v in plan.targets if l == 'Practice'}
    for metric in CAPACITY_METRICS:
        if metric not in practice:
            continue
        roll = sum(v * role_fte.get(l, 0.0)
                   for m, l, v in plan.targets if m == metric and l != 'Practice')
        gap = roll - practice[metric]
        out.append('  %-28s roles %14s  practice %14s  gap %9s'
                   % (metric, '{:,.0f}'.format(roll), '{:,.0f}'.format(practice[metric]),
                      '{:,.0f}'.format(gap)))
    out.append('')
    return '\n'.join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--tenant', type=int, required=True)
    ap.add_argument('--apply', action='store_true',
                    help='write to the AppDB (default is a dry run)')
    ap.add_argument('--fy', type=int, default=None)
    ap.add_argument('--phase', choices=('all', 'rates', 'targets'), default='all',
                    help="'rates' before Orchestrate_Onboarding STEP 6, 'targets' after it -- "
                         "the seeded plan rates feed the capitation that the revenue targets "
                         "are then derived from")
    ap.add_argument('--principal', type=int, default=None, metavar='PRACTITIONER_ID',
                    help='name the principal when the account lookup cannot (a practice with '
                         'several accounts already provisioned)')
    args = ap.parse_args(argv)

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import app as appmod

    conn = appmod._fabric_conn()
    ac = appmod._appdb_conn(autocommit=True)
    try:
        plan = build_plan(conn.cursor(), args.tenant, fy=args.fy,
                          principal_id=args.principal)
        print(format_plan(plan))
        if not args.apply:
            print('DRY RUN -- nothing written. Re-run with --apply to write.\n')
            return 0
        written = apply_plan(ac.cursor(), plan, phase=args.phase)
        print('WROTE roles=%(roles)d pay=%(pay)d plans=%(plans)d targets=%(targets)d\n' % written)
        print('==> A BUILD MUST RUN BEFORE THE CUSTOMER SEES THIS. <== Input.* reaches the\n'
              '    warehouse through Meta.usp_Sync_Input_From_AppDB, and targets do not reach\n'
              '    Gold.Fact_Daily_Targets until the build after that.\n')
        return 0
    finally:
        conn.close()
        ac.close()


if __name__ == '__main__':
    sys.exit(main())
