"""
Seed_Targets_From_Actuals.py
Seed a newly onboarded practice's targets from its own last complete financial year.

    py Scripts/Seed_Targets_From_Actuals.py --tenant 123            # dry run, prints everything
    py Scripts/Seed_Targets_From_Actuals.py --tenant 123 --apply    # writes Input.Targets

==> THIS EXISTS TO MAKE THE HOME PAGE LIGHT UP ON DAY ONE. <==
A tile with no target renders blank, so a practice that signs up and finds a board of grey
squares has been shown nothing. These are deliberately CRUDE ballpark numbers -- last year's
actual, copied across, no uplift -- so the first conversation can be "here is where you are,
where do you want to be?" rather than "please fill in forty targets before the product works".

ONBOARDING ONLY. It is not a forecasting tool and must not be re-run over a practice that has
since set real targets: --apply refuses unless the target FY is empty, or --replace is given.

THE THREE RULES, all decided deliberately:

  practice level only   Target_Level = 'Practice'. Per-practitioner targets need role mapping and
                        FTE scaling, and are a conversation with the principal, not a guess.
  no uplift             The target IS last year's actual. An uplift would be a number nobody
                        chose, dressed up as analysis. Range_Type (above/below/within) is
                        deliberately ignored for the same reason.
  no full year, no targets
                        A practice without one COMPLETE financial year gets nothing. Annualising
                        three months into an annual target is a fiction, and a wrong target is
                        worse than a blank one -- it looks authoritative.

WHICH YEAR:
  The tenant's OWN financial year, from Gold.vw_Dim_Date -- NOT Gold.Dim_Date, whose
  Financial_Year_Name is a fixed April-March year. Practice financial years became tenant-specific
  in V193/V194, and Scripts/Generate_Targets_Template.py still reads the generic one, so for any
  practice not on an April year it attributes actuals to the wrong year. Do not copy that query.

  The year chosen is the most recent COMPLETE one (its last day is in the past) at or after the
  practice cutover. Cutover = the first financial year holding >= 100 appointments, the same test
  Gold.usp_Load_Dim_Date_Grouping uses: a practice's history usually has a scatter of stray
  records years before it went live, and without this a 4-row year from 2011 looks like data.

HOW EACH METRIC IS AGGREGATED (matching the DAX, via Config.Metric_Definitions.Target_Type):
  rate            SUM(Numerator) / SUM(Denominator)   -- x100 where Format_Type is percent.
                  NOT the average of daily rates, which would weight a quiet Tuesday equally
                  with a full Monday.
  cumulative      SUM(Numerator) over the year.
  point_in_time   Numerator on the latest date in the year -- a snapshot does not accumulate.

COVERAGE IS REPORTED, NEVER ASSUMED:
  A metric with no actuals gets no target and its tile stays blank. The script prints exactly
  which, because "it worked" and "it half worked" look identical in the database. On the first
  practice tried (Maple) only 24 of 42 metrics had prior-year actuals -- but that is an artefact
  of its history accumulating metric by metric as the product grew. A practice onboarded today
  has its whole history computed with today's metric set, so expect better. Check the number.

AFTERWARDS: the targets reach the warehouse through appdb_sync (Input.Targets ->
Input_Stage.Targets), then Gold.usp_Load_Fact_Daily_Targets and the period aggregate. Run the
build, or wait for the overnight one, before the board shows anything.
"""

import argparse
import struct
import subprocess
import sys
from datetime import datetime, timezone

import pyodbc

WAREHOUSE = ('emeh72n2ntdufpj4q665b2lzx4-eljzajgm5cpe5i64szgon7sej4'
             '.datawarehouse.fabric.microsoft.com')
WAREHOUSE_DB = 'WH_Dentally'
APPDB_SERVER = 'sql-analytically.database.windows.net'
APPDB_DB     = 'AppDB-prod'

MIN_APPOINTMENTS = 100   # the cutover test, as used by Gold.usp_Load_Dim_Date_Grouping


def _token():
    return subprocess.check_output(
        ['az', 'account', 'get-access-token', '--resource',
         'https://database.windows.net', '--query', 'accessToken', '-o', 'tsv'],
        shell=True).decode().strip().encode('utf-16-le')


def connect(server, database):
    tb = _token()
    return pyodbc.connect(
        'Driver={ODBC Driver 18 for SQL Server};Server=%s,1433;Database=%s;'
        'Encrypt=yes;TrustServerCertificate=no;' % (server, database),
        attrs_before={1256: struct.pack('<I%ds' % len(tb), len(tb), tb)}, autocommit=True)


def pick_year(cur, tenant):
    """(financial_year, name, from, to) of the last COMPLETE year at or after cutover, or None."""
    cur.execute("""
        SELECT d.Financial_Year, MIN(d.Financial_Year_Name), MIN(d.Full_Date), MAX(d.Full_Date),
               COUNT(a.pk_Appointment) AS appts
        FROM   Gold.vw_Dim_Date d
        LEFT JOIN Gold.Fact_Appointments a
               ON a.fk_Date_Start = d.pk_Date AND a.Tenant_ID = d.Tenant_ID
        WHERE  d.Tenant_ID = ?
        GROUP BY d.Financial_Year
        ORDER BY d.Financial_Year
    """, tenant)
    years = cur.fetchall()
    if not years:
        return None, 'the tenant has no rows in Gold.vw_Dim_Date'

    real = [y for y in years if (y[4] or 0) >= MIN_APPOINTMENTS]
    if not real:
        return None, ('no financial year holds %d appointments -- nothing here is a real trading '
                      'year yet' % MIN_APPOINTMENTS)

    today = datetime.now(timezone.utc).date()
    complete = [y for y in real if y[3] < today]
    if not complete:
        return None, ('the practice has data but no COMPLETE financial year (earliest real year '
                      'is %s, which has not ended) -- no targets, by design' % real[0][1])
    return complete[-1], None


def read_actuals(cur, tenant, fy):
    """Practice-grain actuals for one financial year, aggregated per Target_Type."""
    cur.execute("""
        WITH base AS (
            SELECT a.Metric, a.fk_Date, a.Numerator, a.Denominator,
                   md.Target_Type, md.Format_Type,
                   ROW_NUMBER() OVER (PARTITION BY a.Metric ORDER BY a.fk_Date DESC) AS rn
            FROM   Gold.Fact_Metric_Actuals a
            JOIN   Gold.vw_Dim_Date d
                   ON d.pk_Date = a.fk_Date AND d.Tenant_ID = a.Tenant_ID
            JOIN   Config.Metric_Definitions md ON md.Metric_Key = a.Metric
            WHERE  a.Tenant_ID = ?
              AND  d.Financial_Year = ?
              AND  a.fk_Practice_Site = -1      -- practice grain: not a site
              AND  a.fk_Practitioner  = -1      -- practice grain: not a practitioner
              AND  md.Is_Active = 1
              AND  md.Target_Type IS NOT NULL
        )
        SELECT Metric,
               MAX(Target_Type),
               CASE
                   WHEN MAX(CASE WHEN Denominator IS NOT NULL THEN 1 ELSE 0 END) = 1
                       THEN (CASE WHEN MAX(Format_Type) = 'percent' THEN 100.0 ELSE 1 END)
                            * SUM(Numerator) / NULLIF(SUM(Denominator), 0)
                   WHEN MAX(Target_Type) = 'cumulative' THEN SUM(Numerator)
                   ELSE MAX(CASE WHEN rn = 1 THEN Numerator END)
               END AS Target_Value
        FROM   base
        GROUP  BY Metric
    """, tenant, fy)
    # ==> A ZERO TARGET IS WORSE THAN A BLANK ONE. <== Blank reads as "no target set"; zero reads
    # as a target that is met forever, and every tile scored against it sits at 100%+ looking
    # healthy. Dev's tenant 100 produced nhs_revenue = 0 from a year with real NHS income, which
    # is exactly the shape of a wrong number that looks authoritative. Same rule as the
    # no-complete-year one: say nothing rather than something false.
    return {r[0]: (r[1], float(r[2]))
            for r in cur.fetchall() if r[2] is not None and float(r[2]) != 0.0}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tenant', type=int, required=True)
    ap.add_argument('--apply', action='store_true', help='write to Input.Targets (default: dry run)')
    ap.add_argument('--replace', action='store_true',
                    help='overwrite targets that already exist for the destination FY')
    ap.add_argument('--warehouse', default=WAREHOUSE)
    ap.add_argument('--appdb-server', default=APPDB_SERVER)
    ap.add_argument('--appdb-db', default=APPDB_DB)
    a = ap.parse_args()

    wh = connect(a.warehouse, WAREHOUSE_DB)
    cur = wh.cursor()

    year, why = pick_year(cur, a.tenant)
    if year is None:
        print('No targets generated for tenant %d: %s' % (a.tenant, why))
        wh.close()
        return 2
    fy, fy_name, d_from, d_to, appts = year
    print('Source year : %s (%s)  %s .. %s   %s appointments'
          % (fy, fy_name, d_from, d_to, f'{appts:,}'))

    # Targets are written for the year the practice is in NOW.
    cur.execute("SELECT Financial_Year FROM Gold.vw_Dim_Date WHERE Tenant_ID = ? AND Full_Date = ?",
                a.tenant, datetime.now(timezone.utc).date())
    row = cur.fetchone()
    if not row:
        print('Cannot determine the current financial year for tenant %d.' % a.tenant)
        wh.close()
        return 2
    dest_fy = row[0]
    print('Target year : %s' % dest_fy)

    actuals = read_actuals(cur, a.tenant, fy)

    cur.execute("""SELECT Metric_Key FROM Config.Metric_Definitions
                   WHERE Is_Active = 1 AND Target_Type IS NOT NULL ORDER BY Metric_Key""")
    wanted = [r[0] for r in cur.fetchall()]
    wh.close()

    missing = [m for m in wanted if m not in actuals]
    print('\nCoverage    : %d of %d metrics have a usable actual; %d tile(s) will stay blank'
          % (len(actuals), len(wanted), len(missing)))
    print('              (metrics whose actual was zero or null are skipped deliberately -- a '
          'zero target reads as met forever)')

    print('\n%-34s %-14s %s' % ('metric', 'type', 'target'))
    for m in sorted(actuals):
        t, v = actuals[m]
        print('  %-32s %-14s %s' % (m, t, f'{v:,.2f}'))
    if missing:
        print('\nno actuals, no target (tile stays blank):')
        for m in missing:
            print('  %s' % m)

    if not actuals:
        print('\nNothing to write.')
        return 2
    if not a.apply:
        print('\nDRY RUN -- re-run with --apply to write %d target(s).' % len(actuals))
        return 0

    app = connect(a.appdb_server, a.appdb_db)
    acur = app.cursor()
    acur.execute("SELECT COUNT(*) FROM Input.Targets WHERE Tenant_ID = ? AND FY = ?",
                 a.tenant, dest_fy)
    existing = acur.fetchone()[0]
    if existing and not a.replace:
        print('\nREFUSING: tenant %d already has %d target(s) for FY %s. This seeds a NEW practice; '
              'pass --replace only if you are certain those are not real targets someone set.'
              % (a.tenant, existing, dest_fy))
        app.close()
        return 1
    if existing:
        acur.execute("DELETE FROM Input.Targets WHERE Tenant_ID = ? AND FY = ? AND Target_Level = 'Practice'",
                     a.tenant, dest_fy)
        print('\nreplaced %d existing Practice row(s)' % acur.rowcount)

    now = datetime.now(timezone.utc).replace(tzinfo=None)
    acur.fast_executemany = True
    acur.executemany(
        "INSERT INTO Input.Targets (Tenant_ID, FY, Metric, Target_Level, Target_Value, "
        "Updated_At, Updated_By) VALUES (?, ?, ?, 'Practice', ?, ?, 'Seed_Targets_From_Actuals')",
        [(a.tenant, dest_fy, m, round(v, 4), now) for m, (t, v) in sorted(actuals.items())])
    print('wrote %d target(s) to Input.Targets for tenant %d FY %s'
          % (len(actuals), a.tenant, dest_fy))
    app.close()

    print('\nNext: appdb_sync carries these to Input_Stage.Targets (within 10 minutes), then the '
          'build turns them into Gold.Fact_Daily_Targets and the period aggregate.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
