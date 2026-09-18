"""Unit tests for Web/billing_run.py -- the pure logic that decides what a practice is charged.

The Stripe interaction itself is proven against the sandbox by running the script; these cover the
decisions that would be expensive to get wrong and cheap to regress: rounding, who is billable,
which month is billed, how VAT is read back, and -- above all -- that an error can never destroy a
known invoice id, because that is what would let a practice be billed twice.
"""
import os

# billing_run reads its configuration at import time, as a job script reasonably may. Provide it
# before importing rather than restructuring the module for the tests' convenience.
os.environ.setdefault('TENANT_ID', 'test-tenant')
os.environ.setdefault('CLIENT_ID', 'test-client')
os.environ.setdefault('CLIENT_SECRET', 'test-secret')
os.environ.setdefault('FABRIC_SERVER', 'test-server')
os.environ.setdefault('FABRIC_DB', 'WH_Test')

import billing_run as br  # noqa: E402


# ── money ─────────────────────────────────────────────────────────────────────

def test_pence_rounds_half_up_not_toward_zero():
    # Pro-rata produces awkward thirds: 60.00 * 16/31 = 30.967..., stored 30.97 by the proc.
    assert br.pence(30.97) == 3097
    assert br.pence(12.39) == 1239
    assert br.pence(3.10) == 310
    assert br.pence(60) == 6000
    assert br.pence(0) == 0


def test_pence_is_exact_for_the_float_cases_that_bite():
    # 2.675 and friends: the danger is int(x*100) truncating 267.49999 to 267.
    assert br.pence(2.67) == 267
    assert br.pence(0.07) == 7
    assert br.pence(178.10) == 17810


# ── which month ───────────────────────────────────────────────────────────────

def test_last_month_is_the_previous_calendar_month_on_any_day(monkeypatch):
    # Must be runnable on ANY day of the following month, not just the 1st. Note this deliberately
    # does NOT use the proc's own NULL default, which derives the month from YESTERDAY and would
    # bill September if run on 18 September.
    from datetime import datetime, timezone

    class _D(datetime):
        _now = None
        @classmethod
        def now(cls, tz=None):
            return cls._now

    for today, expected in ((datetime(2026, 9, 1, tzinfo=timezone.utc), 202608),
                            (datetime(2026, 9, 18, tzinfo=timezone.utc), 202608),
                            (datetime(2026, 9, 30, tzinfo=timezone.utc), 202608),
                            (datetime(2026, 1, 15, tzinfo=timezone.utc), 202512)):
        _D._now = today
        monkeypatch.setattr(br, 'datetime', _D)
        assert br.last_month() == expected, today


# ── who is billable ───────────────────────────────────────────────────────────

def _t(**kw):
    base = {'tenant_id': 100, 'name': 'Maple Dental', 'customer': 'cus_X',
            'paid_from': None, 'cancelled_at': None, 'total_pence': 21372, 'lines': [{}]}
    base.update(kw)
    return base


def test_billable_when_everything_is_in_place():
    assert br.blocked_reason(_t(), has_card=True) is None


def test_not_billable_without_a_stripe_customer():
    assert 'no Stripe customer' in br.blocked_reason(_t(customer=''), has_card=False)


def test_not_billable_without_a_card():
    assert 'no card on file' in br.blocked_reason(_t(), has_card=False)


def test_not_billable_when_there_is_nothing_to_charge():
    # A trial or free-forever month produces lines worth zero. Raising a £0 invoice would email a
    # practice about a bill that does not exist.
    assert 'nothing to bill' in br.blocked_reason(_t(total_pence=0), has_card=True)
    assert 'nothing to bill' in br.blocked_reason(_t(total_pence=-5), has_card=True)


def test_not_billable_once_cancelled():
    from datetime import datetime
    why = br.blocked_reason(_t(cancelled_at=datetime(2026, 8, 1)), has_card=True)
    assert 'cancelled' in why


# ── reading VAT back ──────────────────────────────────────────────────────────

class _Obj:
    def __init__(self, d):
        self._d = d
    def to_dict(self):
        return self._d


def test_vat_read_from_total_taxes():
    # The modern shape. inv.tax does not exist and raises AttributeError rather than returning
    # None, which is how this first surfaced.
    inv = _Obj({'total': 21372, 'total_excluding_tax': 17810,
                'total_taxes': [{'amount': 3562, 'tax_behavior': 'inclusive'}]})
    assert br.invoice_tax_pence(inv) == 3562


def test_vat_read_from_a_legacy_flat_field():
    assert br.invoice_tax_pence(_Obj({'total': 21372, 'tax': 3562})) == 3562


def test_vat_falls_back_to_the_difference():
    assert br.invoice_tax_pence(_Obj({'total': 21372, 'total_excluding_tax': 17810})) == 3562


def test_vat_is_zero_when_no_tax_applied():
    assert br.invoice_tax_pence(_Obj({'total': 6000, 'total_excluding_tax': 6000})) == 0


# ── the guard that matters most ───────────────────────────────────────────────

class _Cur:
    """Records statements and fakes rowcount, so the UPDATE-then-INSERT branch can be exercised."""
    def __init__(self, rowcount=1):
        self.sql, self.rowcount = [], rowcount
    def execute(self, sql, *a):
        self.sql.append((' '.join(sql.split()), a))
        return self


def test_recording_an_error_never_destroys_a_known_invoice_id():
    # THE bug this suite exists for. record() used to DELETE and re-INSERT unconditionally, so a
    # failure AFTER the invoice was created -- even a trivial one in a print -- replaced the good
    # row with an ERROR row and lost the id. The draft then existed in Stripe with nothing pointing
    # at it, so the next run could not discard it and raised a SECOND invoice for the same month.
    cur = _Cur(rowcount=1)
    br.record(cur, _t(), 202608, error=RuntimeError('boom'))
    stmts = [s for s, _ in cur.sql]
    assert not any(s.startswith('DELETE FROM Billing.Stripe_Invoice') for s in stmts), \
        'an error must never delete the row holding the invoice id'
    assert any(s.startswith('UPDATE Billing.Stripe_Invoice') for s in stmts)
    # and the UPDATE must not touch Stripe_Invoice_ID
    upd = next(s for s in stmts if s.startswith('UPDATE'))
    assert 'Stripe_Invoice_ID =' not in upd


def test_recording_an_error_with_no_prior_row_inserts_one():
    cur = _Cur(rowcount=0)          # the UPDATE matched nothing
    br.record(cur, _t(), 202608, error=RuntimeError('boom'))
    stmts = [s for s, _ in cur.sql]
    assert any(s.startswith('INSERT INTO Billing.Stripe_Invoice') for s in stmts)


def test_a_successful_raise_replaces_the_row():
    # Success is allowed to replace outright -- that is how a re-raised draft supersedes the old id.
    cur = _Cur()
    inv = type('I', (), {'id': 'in_NEW', 'status': 'draft', 'total': 21372})()
    br.record(cur, _t(), 202608, invoice=inv)
    stmts = [s for s, _ in cur.sql]
    assert any(s.startswith('DELETE FROM Billing.Stripe_Invoice') for s in stmts)
    ins = next(s for s in stmts if s.startswith('INSERT INTO Billing.Stripe_Invoice'))
    assert 'Stripe_Invoice_ID' in ins
    assert ('in_NEW', 'draft') == (cur.sql[-1][1][2], cur.sql[-1][1][4])
