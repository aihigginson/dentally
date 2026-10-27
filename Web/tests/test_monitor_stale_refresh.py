"""The alarm for a build that completed without refreshing the semantic model.

==> THIS IS THE CHECK THAT WAS MISSING FOR SEVEN NIGHTS. <== From 20/10 to 26/10 the refresh
gate threw on a bad column name, REFRESH_DONE stopped dead, and nothing said so -- the build
logs PARENT_CLOSED SUCCEEDED *before* the refresh runs, so it reported clean while the reports
served whatever the model last held. It was found by a human noticing yesterday's date on the
Day Book.

The rule: the newest REFRESH_DONE must not be older than the newest BUILD_DONE.
"""
import datetime as dt
import os

os.environ.setdefault('TENANT_ID', 'test-tenant')
os.environ.setdefault('CLIENT_ID', 'test-client')
os.environ.setdefault('CLIENT_SECRET', 'test-secret')
os.environ.setdefault('FABRIC_SERVER', 'test-server')
os.environ.setdefault('FABRIC_DB', 'WH_Test')


class _Cur:
    """Answers the monitor's queries in order; only the build/refresh pair varies."""

    description = [('a',), ('b',), ('c',), ('d',), ('e',)]

    def __init__(self, last_build, last_refresh):
        self._pair = (last_build, last_refresh)
        self._last = None

    def execute(self, sql, *args):
        self._last = 'pair' if 'BUILD_DONE' in sql else 'other'
        return self

    def fetchone(self):
        if self._last == 'pair':
            return self._pair
        return None            # no watermark, no bad-token row

    def fetchall(self):
        return []              # no process failures, no ingest failures


class _Conn:
    def __init__(self, cur):
        self._cur = cur

    def cursor(self):
        return self._cur

    def close(self):
        pass


def _run(monkeypatch, appmod, client, last_build, last_refresh):
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _Conn(_Cur(last_build, last_refresh)))
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'sekrit')
    sent = []
    monkeypatch.setattr(appmod, '_send_email', lambda *a, **k: sent.append(a))
    r = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'sekrit'})
    assert r.status_code == 200, r.data
    return r.get_json(), sent


def test_a_build_with_no_refresh_behind_it_raises_the_alarm(appmod, client, monkeypatch):
    """The exact shape of the 20-26 October outage: builds running, refresh stopped dead."""
    body, _ = _run(monkeypatch, appmod, client,
                   dt.datetime(2026, 10, 26, 22, 26), dt.datetime(2026, 10, 19, 21, 31))
    assert body['stale_refresh'] is not None
    assert body['stale_refresh']['days_behind'] == 7
    assert body['stale_refresh']['last_refresh'].startswith('2026-10-19')


def test_a_refresh_that_followed_the_build_is_silent(appmod, client, monkeypatch):
    """The normal night -- refresh minutes after the build -- must not alarm."""
    body, _ = _run(monkeypatch, appmod, client,
                   dt.datetime(2026, 10, 26, 22, 26), dt.datetime(2026, 10, 26, 22, 27))
    assert body['stale_refresh'] is None


def test_a_model_never_refreshed_at_all_raises_the_alarm(appmod, client, monkeypatch):
    """A brand-new environment, or one whose log was trimmed: NULL is not 'fine'."""
    body, _ = _run(monkeypatch, appmod, client, dt.datetime(2026, 10, 26, 22, 26), None)
    assert body['stale_refresh'] is not None
    assert body['stale_refresh']['last_refresh'] == 'never'
    assert body['stale_refresh']['days_behind'] is None


def test_no_build_yet_is_not_an_alarm(appmod, client, monkeypatch):
    """==> SILENCE IS NOT A FAILURE. <== Before the first build there is nothing to refresh
    behind, and alarming on an empty log would make the monitor cry wolf on day one."""
    body, _ = _run(monkeypatch, appmod, client, None, None)
    assert body['stale_refresh'] is None


def test_the_alarm_makes_the_run_actionable_on_its_own(appmod, client, monkeypatch):
    """No process failures, no ingest failures, no bad tokens -- and it must STILL email.

    This is the whole point: during the outage every other signal was clean, which is why
    seven nights passed in silence.
    """
    monkeypatch.setattr(appmod, 'APP_ENV', 'prod')
    body, sent = _run(monkeypatch, appmod, client,
                      dt.datetime(2026, 10, 26, 22, 26), dt.datetime(2026, 10, 19, 21, 31))
    assert body['process_failures'] == 0 and body['ingest_failures'] == 0
    assert body['stale_refresh'] is not None
    assert sent, 'a stale model must email even when nothing else failed'
    subject = sent[0][1]
    assert 'NOT REFRESHED' in subject, subject


def test_the_email_leads_with_the_stale_model(appmod):
    """It goes first because a model nobody refreshed makes every figure under it stale."""
    stale = {'last_build': '2026-10-26 22:26:00', 'last_refresh': '2026-10-19 21:31:00',
             'days_behind': 7}
    body = appmod._monitor_email_body([], [], '2026-10-26', stale)
    assert 'THE SEMANTIC MODEL WAS NOT REFRESHED' in body
    assert '7 day(s) behind' in body
    assert body.index('NOT REFRESHED') < body.index('Investigate in Audit.Unified_Log')


def test_the_email_is_unchanged_when_the_model_is_fresh(appmod):
    """The section must not appear at all on a normal night."""
    body = appmod._monitor_email_body([], [], '2026-10-26')
    assert 'NOT REFRESHED' not in body
