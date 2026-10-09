"""Unit tests for Web/appdb_sync.py -- the alert decision.

This job replaced Azure Monitor for failure notification, so the decision of WHEN to email is now
load-bearing: too eager and it sends 144 emails a day and gets filtered into oblivion; too shy and
an outage passes unnoticed, which is the exact failure it exists to prevent. Everything else in the
job is I/O against two databases and is proved by running it.
"""
import json
import os
from datetime import datetime, timedelta, timezone

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


# ---------------------------------------------------------------------------
#  The fingerprint -- it decides whether the ten-minute job writes anything at
#  all, so a false "unchanged" would silently freeze staging against a source
#  that had moved on. Cheap to test, and the only pure logic in the copy path.
# ---------------------------------------------------------------------------

def test_row_order_is_not_a_content_change():
    # The source SELECT carries no ORDER BY, so the same contents can arrive in a different
    # order on the next run. Treating that as a change would restage all eight tables every
    # ten minutes -- exactly the cost this was written to remove.
    a = [('alice', 1), ('bob', 2), ('carol', 3)]
    assert js._fingerprint(a) == js._fingerprint(list(reversed(a)))


def test_a_changed_value_changes_the_fingerprint():
    assert js._fingerprint([('alice', 1)]) != js._fingerprint([('alice', 2)])


def test_a_new_row_changes_the_fingerprint():
    assert js._fingerprint([('alice', 1)]) != js._fingerprint([('alice', 1), ('bob', 2)])


def test_field_boundaries_cannot_be_forged():
    # Concatenating without a separator would make ('a', 'b') and ('ab',) identical, and an
    # access row could then be edited into a shape that looks unchanged.
    assert js._fingerprint([('a', 'b')]) != js._fingerprint([('ab',)])


def test_none_is_distinct_from_empty_string():
    # NULL and '' mean different things in Application_Users; collapsing them would hide a real
    # edit to a UPN or a display name.
    assert js._fingerprint([(None,)]) != js._fingerprint([('',)])


def test_identical_content_is_stable_across_calls():
    rows = [('alice', 1, None), ('bob', 2, 'x')]
    assert js._fingerprint(rows) == js._fingerprint(list(rows))


# ---------------------------------------------------------------------------
#  _why_run_proc -- whether the ten-minute merge runs at all. A wrong "skip"
#  freezes Security.Application_Users against a source that has moved on, so
#  every path that forces a run is tested, not just the happy one.
# ---------------------------------------------------------------------------

class _ProcCur:
    """Answers the two questions _why_run_proc asks, by looking at the SQL."""
    def __init__(self, last_status='SUCCEEDED', sentinel_age_min=5, sentinel=True):
        self.last_status = last_status
        self.sentinel_age_min = sentinel_age_min
        self.sentinel = sentinel
        self._next = None

    def execute(self, sql, *a):
        if 'Process_Execution_Log' in sql:
            self._next = (self.last_status,) if self.last_status else None
        else:
            if self.sentinel:
                when = (datetime.now(timezone.utc).replace(tzinfo=None)
                        - timedelta(minutes=self.sentinel_age_min))
                self._next = (when,)
            else:
                self._next = None
        return self

    def fetchone(self):
        return self._next


def test_a_changed_table_always_runs_the_merge():
    why, at = js._why_run_proc(_ProcCur(), {'Application_Users'}, NOW)
    assert why and 'Application_Users' in why
    assert at is None                      # staging changed -- no sentinel was read


def test_a_failed_previous_run_forces_the_merge():
    # Staging is correct but the target may be half-written; skipping would make that permanent.
    why, _ = js._why_run_proc(_ProcCur(last_status='FAILED'), set(), NOW)
    assert why and 'FAILED' in why


def test_never_having_run_forces_the_merge():
    why, at = js._why_run_proc(_ProcCur(sentinel=False), set(), NOW)
    assert why and 'no record' in why
    assert at is None


def test_a_stale_merge_self_heals():
    # Whatever the fingerprints say, the merge runs at least this often.
    why, at = js._why_run_proc(_ProcCur(sentinel_age_min=js.PROC_MAX_SKIP_MINUTES + 1), set(), NOW)
    assert why and 'self-heal' in why
    assert at is not None


def test_nothing_changed_and_recently_merged_skips():
    why, at = js._why_run_proc(_ProcCur(sentinel_age_min=5), set(), NOW)
    assert why is None
    # ==> AND IT HANDS BACK THE TIMESTAMP. <== Without this the AppDB mirror has no
    # last-merge time, _fast_skip bails on every run, and the fast path is dead while
    # looking perfectly healthy -- which is exactly what happened for weeks.
    assert at is not None


def test_the_sentinel_cannot_collide_with_a_real_table():
    assert js.PROC_SENTINEL not in js.FULL_TABLES


# ---------------------------------------------------------------------------
#  _fast_skip -- the decision that avoids opening a Fabric session at all.
#
#  4,015 of 4,015 access runs over 14 days had nothing to do, and every one
#  connected to the warehouse to find that out. This decides from the AppDB
#  mirror instead. It is the riskiest function in the file: a wrong "skip"
#  freezes Security.Application_Users against a source that has moved on, and
#  unlike _why_run_proc it does so WITHOUT the warehouse ever being consulted.
#
#  So every uncertainty must return None (= go the Fabric route). These test
#  that, not just the happy path.
# ---------------------------------------------------------------------------

class _LocalCur:
    """Stands in for the AppDB cursor: serves Input.Sync_State, then source tables."""

    def __init__(self, state=None, rows=None, blow_up_on_source=False):
        self.state = state
        self.rows = rows if rows is not None else _nonempty_rows()
        self.blow_up_on_source = blow_up_on_source
        self._next = []

    def execute(self, sql, *a):
        if 'Sync_State' in sql:
            if self.state is None:
                raise RuntimeError('Invalid object name Input.Sync_State')
            self._next = self.state
        else:
            if self.blow_up_on_source:
                raise RuntimeError('source unavailable')
            for t in js.FULL_TABLES:
                if f'[{t}]' in sql:
                    self._next = self.rows[t]
                    break
            else:
                self._next = []
        return self

    def fetchall(self):
        return self._next


def _nonempty_rows():
    """Every table one row. The NONEMPTY floors (Application_Users, Targets) make an all-empty
    fixture fall through on the floor check rather than on the thing under test."""
    return {t: [('a row',)] for t in js.FULL_TABLES}


def _state(age_min=5, status='SUCCEEDED', rows=None, cols=None, drop=(), force_age_h=1):
    """A cache that says 'nothing has changed', which individual tests then spoil."""
    rows = rows if rows is not None else _nonempty_rows()
    cols = cols if cols is not None else {t: ['A'] for t in js.FULL_TABLES}
    when = NOW - timedelta(minutes=age_min)        # relative to the suite's fixed NOW
    out = []
    for t in js.FULL_TABLES:
        out.append((t, len(rows[t]), js._fingerprint(rows[t]), None, when))
    out.append((js.COLS_SENTINEL, None, None, json.dumps(cols), when))
    out.append((js.STATUS_SENTINEL, None, status, None, when))
    out.append((js.PROC_SENTINEL, 0, '0' * 64, when.isoformat(), when))
    out.append((js.FORCE_SENTINEL, None, 'forced', None,
                NOW - timedelta(hours=force_age_h)))
    return [r for r in out if r[0] not in drop]


def test_unchanged_everything_skips_without_touching_fabric():
    why = js._fast_skip(_LocalCur(_state()), NOW)
    assert why and 'no Fabric session opened' in why


# ==> THE TEST THAT WOULD HAVE CAUGHT IT. <== Every _fast_skip test above builds the cache by
# hand, so they all passed while the thing that WRITES the cache never wrote the row the skip
# depends on. _mirror_local omitted PROC_SENTINEL and _fast_skip bailed on every run for weeks --
# in production, silently, because falling through to Fabric is the safe direction and looks
# exactly like working. A hand-built fixture can only test the half you remembered to build.
#
# So: write the cache the way the job writes it, then ask the skip to read it back.

class _RoundTripCur:
    """Captures _save_local writes, then serves them back to _fast_skip as Input.Sync_State."""

    def __init__(self, rows):
        self.saved = {}
        self._rows = rows
        self._next = None

    def execute(self, sql, *args):
        if sql.startswith('DELETE FROM [Input].[Sync_State]'):
            self.saved.pop(args[0], None)
        elif sql.startswith('INSERT INTO [Input].[Sync_State]'):
            item, row_count, fingerprint, payload = args
            self.saved[item] = (row_count, fingerprint, payload, NOW)
        elif sql.startswith('SELECT Item, Row_Count'):
            self._next = [(k,) + v for k, v in self.saved.items()]
        elif sql.startswith('SELECT '):
            table = sql.split('FROM [Input].[')[1].split(']')[0]
            self._next = self._rows[table]
        return self

    def fetchall(self):
        return self._next


def test_what_the_job_writes_is_what_the_skip_can_read():
    rows = _nonempty_rows()
    cur = _RoundTripCur(rows)
    fps = {t: (len(rows[t]), js._fingerprint(rows[t])) for t in js.FULL_TABLES}
    colmap = {t: ['A'] for t in js.FULL_TABLES}

    # Exactly the call the job makes on a run where the merge was skipped.
    js._mirror_local(cur, fps, colmap, 'SUCCEEDED', forced=True,
                     proc_ran_at=NOW - timedelta(minutes=5))

    assert js.PROC_SENTINEL in cur.saved, 'the mirror must write the row the skip depends on'
    why = js._fast_skip(cur, NOW)
    assert why and 'no Fabric session opened' in why


def test_the_mirrored_merge_time_is_the_warehouse_one_not_now():
    # _save_local stamps Updated_At with now on every write, so mirroring "now" on a skipped run
    # would reset the self-heal clock and the 60-minute backstop could never fire. The real
    # timestamp travels in Payload; a merge older than the window must still fall through.
    rows = _nonempty_rows()
    cur = _RoundTripCur(rows)
    fps = {t: (len(rows[t]), js._fingerprint(rows[t])) for t in js.FULL_TABLES}
    js._mirror_local(cur, fps, {t: ['A'] for t in js.FULL_TABLES}, 'SUCCEEDED', forced=True,
                     proc_ran_at=NOW - timedelta(minutes=js.PROC_MAX_SKIP_MINUTES + 1))

    assert js._fast_skip(cur, NOW) is None, 'a stale merge must self-heal, not skip for ever'


def test_a_missing_cache_falls_through_to_fabric():
    # V153 not applied yet, or first run. Must behave exactly as before.
    assert js._fast_skip(_LocalCur(None), NOW) is None


def test_a_changed_row_falls_through_to_fabric():
    cache = _state()
    live = _nonempty_rows()
    live[js.FULL_TABLES[0]] = [('a row',), ('one more',)]
    assert js._fast_skip(_LocalCur(cache, rows=live), NOW) is None


def test_a_failed_previous_run_falls_through_to_fabric():
    assert js._fast_skip(_LocalCur(_state(status='FAILED')), NOW) is None


def test_a_stale_merge_falls_through_to_fabric():
    stale = _state(age_min=js.PROC_MAX_SKIP_MINUTES + 1)
    assert js._fast_skip(_LocalCur(stale), NOW) is None


def test_a_missing_sentinel_falls_through_to_fabric():
    for sentinel in (js.PROC_SENTINEL, js.STATUS_SENTINEL, js.COLS_SENTINEL):
        assert js._fast_skip(_LocalCur(_state(drop=(sentinel,))), NOW) is None, sentinel


def test_an_unparseable_column_map_falls_through_to_fabric():
    bad = [r if r[0] != js.COLS_SENTINEL else (r[0], None, None, 'not json', r[4])
           for r in _state()]
    assert js._fast_skip(_LocalCur(bad), NOW) is None


def test_a_table_missing_from_the_column_map_falls_through_to_fabric():
    cols = {t: ['A'] for t in js.FULL_TABLES}
    del cols[js.FULL_TABLES[0]]
    assert js._fast_skip(_LocalCur(_state(cols=cols)), NOW) is None


def test_an_unreadable_source_falls_through_to_fabric():
    assert js._fast_skip(_LocalCur(_state(), blow_up_on_source=True), NOW) is None


def test_a_source_below_its_floor_falls_through_to_fabric():
    # Application_Users going empty is the one input that could do real harm; the Fabric path
    # raises a proper error for it, so the fast path must not quietly skip instead.
    empty = dict(_nonempty_rows())
    empty['Application_Users'] = []
    assert js._fast_skip(_LocalCur(_state(rows=empty), rows=empty), NOW) is None


def test_a_future_dated_sentinel_falls_through_to_fabric():
    # Clock skew between AppDB and the job host. A negative age must not authorise a skip --
    # it would keep authorising one for as long as the skew lasted.
    assert js._fast_skip(_LocalCur(_state(age_min=-30)), NOW) is None


# ---------------------------------------------------------------------------
#  The daily forced restage. Nothing else ever rewrites Input_Stage
#  unconditionally -- the "nightly full sync" the code used to reference was
#  never a scheduled job -- so this is what re-proves that staging still
#  matches source. It must therefore outrank "nothing changed".
# ---------------------------------------------------------------------------

class _DueCur:
    """Serves the single FORCE_SENTINEL lookup _restage_due makes."""
    def __init__(self, age_h=1, present=True, blow_up=False):
        self.age_h, self.present, self.blow_up = age_h, present, blow_up
        self._next = None

    def execute(self, sql, *a):
        if self.blow_up:
            raise RuntimeError('no such table')
        self._next = (NOW - timedelta(hours=self.age_h),) if self.present else None
        return self

    def fetchone(self):
        return self._next


def test_a_recent_restage_is_not_due():
    assert js._restage_due(_DueCur(age_h=1), NOW) is False


def test_an_aged_out_restage_is_due():
    assert js._restage_due(_DueCur(age_h=js.FORCE_MAX_AGE_HOURS + 1), NOW) is True


def test_never_having_restaged_is_due():
    # First run after this ships, or a cleared cache. Costs one slow run; re-establishes the
    # invariant the whole fingerprint skip depends on.
    assert js._restage_due(_DueCur(present=False), NOW) is True


def test_an_unreadable_sentinel_is_due():
    assert js._restage_due(_DueCur(blow_up=True), NOW) is True


def test_a_future_dated_restage_is_due():
    # Clock skew must not postpone the one thing that re-proves staging.
    assert js._restage_due(_DueCur(age_h=-5), NOW) is True


def test_a_due_restage_beats_nothing_changed():
    # Even with every fingerprint matching, the fast path must stand aside so the restage runs.
    due = _state(force_age_h=js.FORCE_MAX_AGE_HOURS + 1)
    assert js._fast_skip(_LocalCur(due), NOW) is None


def test_a_missing_force_sentinel_falls_through_to_fabric():
    assert js._fast_skip(_LocalCur(_state(drop=(js.FORCE_SENTINEL,))), NOW) is None
