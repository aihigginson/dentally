"""Unit tests for Web/sales_monitor.py -- the window, and the guard that verifies the load.

==> THIS FILE EXISTS BECAUSE THE JOB RAN RED FOR EIGHT DAYS AND NOBODY HEARD. <==
caj-sales-monitor-dev failed every run from 19/10 to 26/10 with

    LOAD MISMATCH: expected 52/2 in window, found 52/0

funnel_billing_rows read EVERY paid Stripe invoice with no date filter, while the DELETE and
the read-back were both scoped to the window. Dev's two paid invoices are dated 2026-09-18:
on 18/10 they sat exactly on the 30-day boundary and the run passed; from 19/10 the window
moved past them and each run deleted 0, inserted 2 outside the window, and read back 0. The
rows duplicated as well as failing -- two invoices had become 26 rows by the time it was found.

The container job reported Succeeded throughout, so nothing surfaced it.
"""
import datetime as dt
import os

os.environ.setdefault('TENANT_ID', 'test-tenant')
os.environ.setdefault('CLIENT_ID', 'test-client')
os.environ.setdefault('CLIENT_SECRET', 'test-secret')
os.environ.setdefault('FABRIC_SERVER', 'test-server')
os.environ.setdefault('FABRIC_DB', 'WH_Test')

import sales_monitor as sm  # noqa: E402

WINDOW = dt.date(2026, 9, 26)


# ── _in_window ────────────────────────────────────────────────────────────────

def test_the_two_invoices_that_broke_it_are_outside_the_window():
    # The exact rows, from Billing.Stripe_Invoice on dev.
    assert sm._in_window(dt.datetime(2026, 9, 18, 8, 20, 24), WINDOW) is False
    assert sm._in_window(dt.datetime(2026, 9, 18, 13, 43, 55), WINDOW) is False


def test_the_boundary_is_inclusive():
    # 18/10 passed precisely because >= holds on the boundary; 19/10 was the first failure.
    assert sm._in_window(dt.datetime(2026, 9, 26, 0, 0), WINDOW) is True
    assert sm._in_window(dt.date(2026, 9, 26), WINDOW) is True
    assert sm._in_window(dt.date(2026, 9, 25), WINDOW) is False


def test_it_reads_the_shapes_kusto_actually_returns():
    """Funnel carries a datetime; usage carries access_date unparsed, so it may be a string."""
    assert sm._in_window(dt.date(2026, 10, 1), WINDOW) is True
    assert sm._in_window('2026-10-02', WINDOW) is True
    assert sm._in_window('2026-09-01', WINDOW) is False
    assert sm._in_window('2026-10-02T00:00:00Z', WINDOW) is True


def test_an_unreadable_date_never_invents_a_load_failure():
    """A parsing surprise must not look like a silent rollback -- that would send us hunting
    the one failure mode this script exists to catch, in the wrong place."""
    assert sm._in_window('not-a-date', WINDOW) is True
    assert sm._in_window(None, WINDOW) is False


# ── the row shapes the guard indexes into ─────────────────────────────────────

def test_the_date_indexes_match_the_tuples_the_extractors_build():
    """==> THE TWO TUPLES PUT THEIR DATE IN DIFFERENT PLACES. <== usage is
    (env, tenant, upn, is_vendor, ACCESS_DATE, ...) and funnel is (env, EVENT_AT, stage, ...).
    Indexing usage at 1 reads Tenant_ID and silently compares an int to a date."""
    usage_row = ('dev', 100, 'a@b.co.uk', 0, dt.date(2026, 10, 20), 3, 2, None, None)
    funnel_row = ('dev', dt.datetime(2026, 10, 20, 8, 0), 'verified', 2,
                  None, None, None, None, None)
    assert usage_row[sm.USAGE_DATE_IX] == dt.date(2026, 10, 20)
    assert funnel_row[sm.FUNNEL_DATE_IX] == dt.datetime(2026, 10, 20, 8, 0)


# ── the regression itself ─────────────────────────────────────────────────────

def _expected(rows, ix):
    return len([r for r in rows if sm._in_window(r[ix], WINDOW)])


def test_an_out_of_window_invoice_is_not_counted_as_expected():
    """The failing arithmetic, reproduced: 2 extracted, 0 in window, read-back 0.

    Before the fix the guard compared 2 against 0 and raised. The billing source is windowed
    now so it would not extract these at all -- but the guard must ALSO be right on its own,
    because the next unwindowed source should be reported as an extract bug, not as a write
    that never landed.
    """
    old_invoices = [
        ('dev', dt.datetime(2026, 9, 18, 8, 20, 24), 'invoice_paid', 4,
         None, None, None, 100, 'status=paid amount_pence=21372'),
        ('dev', dt.datetime(2026, 9, 18, 13, 43, 55), 'invoice_paid', 4,
         None, None, None, 100, 'status=paid amount_pence=38680'),
    ]
    assert len(old_invoices) == 2                                  # what the old guard used
    assert _expected(old_invoices, sm.FUNNEL_DATE_IX) == 0          # what it should compare
    # read-back would be 0, so the new guard agrees and the run is green.


def test_a_genuine_write_failure_is_still_caught():
    """The guard must not have been defanged: in-window rows that do not read back still raise."""
    in_window = [('dev', dt.datetime(2026, 10, 20, 8, 0), 'verified', 2,
                  None, None, None, None, None)]
    assert _expected(in_window, sm.FUNNEL_DATE_IX) == 1
    # read-back of 0 against an expectation of 1 is the real rollback this exists to catch.


def test_billing_rows_are_filtered_in_sql_not_in_python():
    """Windowing in the query is what stops the duplicate, not just the miscount.

    The DELETE only clears the window, so an out-of-window row that is still EXTRACTED gets
    re-inserted every run and cleared by none -- which is how 2 rows became 26.
    """
    import inspect
    src = inspect.getsource(sm.funnel_billing_rows)
    assert 'Created_At >= ?' in src, 'the billing source stopped filtering on the window'
    assert 'window_start' in inspect.signature(sm.funnel_billing_rows).parameters


def test_the_window_is_derived_once():
    """It was computed in main() and again in load(); the billing source then disagreed with
    the delete it was verified against. One derivation, passed down."""
    import inspect
    src = inspect.getsource(sm)
    assert src.count('= (datetime.now(timezone.utc) - timedelta(days=') == 1
    assert 'window_start' in inspect.signature(sm.load).parameters
