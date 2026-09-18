"""Unit tests for Web/appdb_sync.py -- the alert decision.

This job replaced Azure Monitor for failure notification, so the decision of WHEN to email is now
load-bearing: too eager and it sends 144 emails a day and gets filtered into oblivion; too shy and
an outage passes unnoticed, which is the exact failure it exists to prevent. Everything else in the
job is I/O against two databases and is proved by running it.
"""
import os
from datetime import datetime, timedelta

os.environ.setdefault('TENANT_ID', 'test-tenant')
os.environ.setdefault('CLIENT_ID', 'test-client')
os.environ.setdefault('CLIENT_SECRET', 'test-secret')
os.environ.setdefault('APPDB_SERVER', 'test-sql')
os.environ.setdefault('APPDB_DB', 'AppDB-dev')
os.environ.setdefault('FABRIC_SERVER', 'test-server')
os.environ.setdefault('FABRIC_DB', 'WH_Test')

import appdb_sync as js  # noqa: E402

NOW = datetime(2026, 9, 18, 12, 0, 0)


class _Cur:
    """Returns a canned run history, newest first -- the shape _alert_decision queries for."""
    def __init__(self, history):
        self._h = history

    def execute(self, *a, **k):
        return self

    def fetchall(self):
        return self._h


def _runs(*statuses, every_minutes=10, start=NOW):
    """Newest-first history: _runs('FAILED', 'SUCCEEDED') = failed most recently, succeeded before."""
    return [(s, start - timedelta(minutes=every_minutes * (i + 1))) for i, s in enumerate(statuses)]


# ── the transition into failure ───────────────────────────────────────────────

def test_first_failure_after_a_success_alerts():
    kind, detail = js._alert_decision(_Cur(_runs('SUCCEEDED', 'SUCCEEDED')), 'p', NOW, 'FAILED')
    assert kind == 'failed' and detail == 'first failure'


def test_a_failure_with_no_history_at_all_alerts():
    # A brand new job, or a log that has been cleared. Silence would be the wrong default.
    kind, _ = js._alert_decision(_Cur([]), 'p', NOW, 'FAILED')
    assert kind == 'failed'


# ── not spamming while it stays broken ────────────────────────────────────────

def test_a_repeat_failure_inside_the_window_stays_quiet():
    # The access job runs every 10 minutes. Without this it would send 6 emails an hour.
    kind, _ = js._alert_decision(_Cur(_runs(*['FAILED'] * 5)), 'p', NOW, 'FAILED')
    assert kind is None


def test_it_speaks_up_again_exactly_when_the_repeat_window_passes(monkeypatch):
    monkeypatch.setattr(js, 'ALERT_REPEAT_HOURS', 6)
    # At 10 minutes a run, six hours of failure is 36 runs. The reminder must land on the run that
    # CROSSES the boundary and on no other -- one run earlier is still inside the first window, one
    # later is already inside the second and would be a duplicate.
    assert js._alert_decision(_Cur(_runs(*['FAILED'] * 35)), 'p', NOW, 'FAILED')[0] is None
    kind, detail = js._alert_decision(_Cur(_runs(*['FAILED'] * 36)), 'p', NOW, 'FAILED')
    assert kind == 'failed' and 'still failing' in detail
    assert js._alert_decision(_Cur(_runs(*['FAILED'] * 37)), 'p', NOW, 'FAILED')[0] is None


def test_the_reminder_fires_once_per_window_not_every_run(monkeypatch):
    monkeypatch.setattr(js, 'ALERT_REPEAT_HOURS', 6)
    sent = 0
    # Walk a 12-hour outage run by run and count the alerts. Azure Monitor would send one; every
    # run would send 72. The intent is one at the start plus one per six-hour window.
    for n in range(1, 73):
        history = _runs(*['FAILED'] * n)
        kind, _ = js._alert_decision(_Cur(history), 'p', NOW, 'FAILED')
        if kind:
            sent += 1
    assert sent == 2, f'expected 2 reminders across 12h, got {sent}'


def test_a_zero_repeat_window_disables_reminders(monkeypatch):
    monkeypatch.setattr(js, 'ALERT_REPEAT_HOURS', 0)
    kind, _ = js._alert_decision(_Cur(_runs(*['FAILED'] * 100)), 'p', NOW, 'FAILED')
    assert kind is None


# ── recovery ──────────────────────────────────────────────────────────────────

def test_the_first_success_after_a_failure_says_so():
    kind, detail = js._alert_decision(_Cur(_runs('FAILED', 'FAILED', 'SUCCEEDED')), 'p', NOW,
                                      'SUCCEEDED')
    assert kind == 'recovered'
    assert '2 failed run(s)' in detail


def test_an_ordinary_success_is_silent():
    # 144 "it worked" emails a day is how an alert channel becomes wallpaper.
    kind, _ = js._alert_decision(_Cur(_runs('SUCCEEDED', 'SUCCEEDED')), 'p', NOW, 'SUCCEEDED')
    assert kind is None


def test_a_success_with_no_history_is_silent():
    kind, _ = js._alert_decision(_Cur([]), 'p', NOW, 'SUCCEEDED')
    assert kind is None


# ── failing open ──────────────────────────────────────────────────────────────

class _Broken:
    def cursor(self):
        raise RuntimeError('warehouse unreachable')


def test_it_emails_anyway_when_the_history_cannot_be_read(monkeypatch):
    # The Fabric capacity being down is BOTH a likely cause of the failure and the reason the
    # history is unreadable. Going quiet in exactly that case would be the worst possible choice,
    # so an unreadable history alerts rather than suppresses.
    sent = []
    monkeypatch.setattr(js, '_send_alert_email', lambda s, b: sent.append((s, b)))
    js._alert(_Broken(), 'access', NOW, 'FAILED', error=RuntimeError('capacity paused'))
    assert len(sent) == 1
    subject, body = sent[0]
    assert 'FAILED' in subject
    assert 'capacity paused' in body
    assert 'could not read run history' in body


def test_a_recovery_stays_quiet_when_the_history_cannot_be_read(monkeypatch):
    # The mirror case must NOT fail open: announcing a recovery we cannot substantiate would be
    # worse than saying nothing.
    sent = []
    monkeypatch.setattr(js, '_send_alert_email', lambda s, b: sent.append(s))
    js._alert(_Broken(), 'access', NOW, 'SUCCEEDED')
    assert sent == []


def test_an_alert_failure_never_escapes(monkeypatch):
    # _alert is called from the exception handler, immediately before the real error is re-raised.
    # If it threw, a mail problem would replace the sync error in the traceback and send us
    # chasing the wrong fault entirely.
    def _boom(*a, **k):
        raise RuntimeError('graph is down')
    monkeypatch.setattr(js, '_send_alert_email', _boom)
    js._alert(_Cur(_runs('SUCCEEDED')) and _Conn(_runs('SUCCEEDED')), 'access', NOW, 'FAILED',
              error=ValueError('the real error'))


class _Conn:
    def __init__(self, history):
        self._h = history

    def cursor(self):
        return _Cur(self._h)


# ── the message ───────────────────────────────────────────────────────────────

def test_the_failure_email_carries_the_error_and_the_environment(monkeypatch):
    # The whole reason for replacing Azure Monitor: it could only say "an execution failed".
    sent = []
    monkeypatch.setattr(js, '_send_alert_email', lambda s, b: sent.append((s, b)))
    js._alert(_Conn(_runs('SUCCEEDED')), 'access', NOW, 'FAILED',
              error=RuntimeError('row counts differ for Targets -- procs NOT run'))
    subject, body = sent[0]
    assert js.APP_ENV in subject and 'access' in subject
    assert 'row counts differ for Targets' in body
    assert js.APPDB_DB in body


def test_a_none_connection_is_opened_rather_than_failing_open(monkeypatch):
    """THE bug this suite missed, found only by breaking the real job.

    AppDB unreachable -- the commonest failure, and the one this job exists to survive -- raises
    before tgt_cn is ever assigned, so _alert was handed None. None.cursor() blew up, the fail-open
    branch caught it and emailed anyway, and dedup never ran: one broken run sent FOUR identical
    alerts (two executions x replicaRetryLimit 1). Every test here passed throughout, because they
    all handed _alert a working connection.
    """
    sent, opened = [], []
    monkeypatch.setattr(js, '_send_alert_email', lambda s, b: sent.append((s, b)))
    monkeypatch.setattr(js, '_token_struct', lambda: b'token')
    monkeypatch.setattr(js, '_connect', lambda *a, **k: opened.append(a) or _Conn(_runs('FAILED')))

    js._alert(None, 'access', NOW, 'FAILED', error=RuntimeError('AppDB unreachable'))

    assert opened, 'it must open its own connection rather than give up on the history'
    assert sent == [], 'the previous run already failed -- this is a repeat, not a transition'


def test_a_none_connection_still_alerts_on_the_first_failure(monkeypatch):
    # The mirror: opening its own connection must not make it go quiet when it SHOULD speak.
    sent = []
    monkeypatch.setattr(js, '_send_alert_email', lambda s, b: sent.append((s, b)))
    monkeypatch.setattr(js, '_token_struct', lambda: b'token')
    monkeypatch.setattr(js, '_connect', lambda *a, **k: _Conn(_runs('SUCCEEDED')))

    js._alert(None, 'access', NOW, 'FAILED', error=RuntimeError('AppDB unreachable'))
    assert len(sent) == 1
    assert 'AppDB unreachable' in sent[0][1]


def test_the_history_connection_is_closed(monkeypatch):
    closed = []

    class _C(_Conn):
        def close(self):
            closed.append(True)

    monkeypatch.setattr(js, '_send_alert_email', lambda s, b: None)
    monkeypatch.setattr(js, '_token_struct', lambda: b'token')
    monkeypatch.setattr(js, '_connect', lambda *a, **k: _C(_runs('SUCCEEDED')))
    js._alert(None, 'access', NOW, 'FAILED', error=RuntimeError('x'))
    assert closed, 'a connection opened here must not leak -- this runs every ten minutes'
