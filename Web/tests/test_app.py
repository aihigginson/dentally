"""Unit tests for Web/app.py — auth, tenant-scoping, and the fail-closed embed token.

These cover the security-critical paths: token -> UPN, UPN -> (client, tenants),
and that the embed endpoint refuses to mint a token unless RLS roles are set AND
the caller is a provisioned tenant user. Everything external is monkeypatched.
"""
import jwt
from conftest import FakeCursor, FakeConn


# ── /health + /api/auth-config (unauthenticated) ──────────────────────────────

def test_health_ok(client):
    r = client.get('/health')
    assert r.status_code == 200
    assert r.get_json() == {'status': 'ok'}


def test_auth_config(client):
    j = client.get('/api/auth-config').get_json()
    assert j == {'client_id': 'test-client', 'tenant_id': 'test-tenant'}


# ── _auth(): Bearer ID token -> upn ───────────────────────────────────────────

def test_auth_missing_header(appmod):
    with appmod.app.test_request_context('/', headers={}):
        upn, err = appmod._auth()
    assert upn is None and err[1] == 401


def test_auth_non_bearer(appmod):
    with appmod.app.test_request_context('/', headers={'Authorization': 'Basic abc'}):
        upn, err = appmod._auth()
    assert upn is None and err[1] == 401


def test_auth_valid_lowercases_upn(appmod, monkeypatch):
    monkeypatch.setattr(appmod, '_validate_id_token',
                        lambda t: {'preferred_username': 'User@Practice.CO.UK'})
    with appmod.app.test_request_context('/', headers={'Authorization': 'Bearer x'}):
        upn, err = appmod._auth()
    assert err is None and upn == 'user@practice.co.uk'


def test_auth_expired(appmod, monkeypatch):
    def _expired(t):
        raise jwt.ExpiredSignatureError()
    monkeypatch.setattr(appmod, '_validate_id_token', _expired)
    with appmod.app.test_request_context('/', headers={'Authorization': 'Bearer x'}):
        upn, err = appmod._auth()
    assert upn is None and err[1] == 401


def test_auth_no_upn_claim(appmod, monkeypatch):
    monkeypatch.setattr(appmod, '_validate_id_token', lambda t: {'sub': 'no-upn'})
    with appmod.app.test_request_context('/', headers={'Authorization': 'Bearer x'}):
        upn, err = appmod._auth()
    assert upn is None and err[1] == 401


# ── _get_user_info(): UPN -> (display, client, tenant_ids, maintain) ──────────

def test_get_user_info_unprovisioned(appmod):
    cur = FakeCursor(one_row=None, all_rows=[])
    assert appmod._get_user_info(cur, 'nobody@x.com') == (None, None, [], False)


def _user_row(appmod, name, client_id, maintain, *modules):
    """Display_Name, Client_ID, Maintain_Targets, then one flag per _ALL_MODULE_COLS."""
    flags = list(modules) + [0] * (len(appmod._ALL_MODULE_COLS) - len(modules))
    return (name, client_id, maintain) + tuple(flags)


def test_get_user_info_provisioned(appmod):
    cur = FakeCursor(one_row=_user_row(appmod, 'Alice', 7, 1, 1), all_rows=[(11,), (12,)])
    name, client_id, tids, maintain = appmod._get_user_info(cur, 'alice@x.com')
    assert name == 'Alice'
    assert client_id == 7
    assert tids == [11, 12]
    assert maintain is True


def test_get_user_info_module_only_no_admin(appmod):
    """A plain user (one module, not an admin) is still provisioned."""
    cur = FakeCursor(one_row=_user_row(appmod, 'Bob', 7, 0, 1), all_rows=[(11,)])
    name, client_id, tids, maintain = appmod._get_user_info(cur, 'bob@x.com')
    assert (name, client_id, tids, maintain) == ('Bob', 7, [11], False)


def test_get_user_info_access_less_row_fails_closed(appmod):
    """A stale all-zero row (no module, no admin) must NOT confer identity.

    These rows accumulate when the AppDB->warehouse sync stops running: prod held 61 of them.
    They are harmless for reports (gated per module) but /api/targets gates on client_id only,
    so a row like this could read and write a practice's targets.
    """
    cur = FakeCursor(one_row=_user_row(appmod, 'Stale', 100, 0), all_rows=[(100,)])
    assert appmod._get_user_info(cur, 'stale@x.com') == (None, None, [], False)


# ── /api/embed-token: fail-closed RLS ─────────────────────────────────────────

def test_embed_requires_auth(client):
    assert client.get('/api/embed-token?report=revenue').status_code == 401


def test_embed_unknown_report(client, appmod, monkeypatch):
    monkeypatch.setattr(appmod, '_auth', lambda: ('u@x.com', None))
    assert client.get('/api/embed-token?report=nope').status_code == 404


def test_embed_refuses_when_roles_empty(client, appmod, monkeypatch):
    # Fail closed: no RLS role configured -> never mint an (unfiltered) token.
    monkeypatch.setattr(appmod, '_auth', lambda: ('u@x.com', None))
    monkeypatch.setattr(appmod, 'REPORT_ROLES', [])
    assert client.get('/api/embed-token?report=revenue').status_code == 500


def test_embed_forbids_unprovisioned_user(client, appmod, monkeypatch):
    # Roles are set, but the caller maps to no tenant -> 403, no token.
    monkeypatch.setattr(appmod, '_auth', lambda: ('u@x.com', None))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: FakeConn())
    monkeypatch.setattr(appmod, '_get_user_info', lambda cur, upn: (None, None, [], False))
    assert client.get('/api/embed-token?report=revenue').status_code == 403


def test_embed_success_for_provisioned_user(client, appmod, monkeypatch):
    monkeypatch.setattr(appmod, '_auth', lambda: ('u@x.com', None))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: FakeConn())
    monkeypatch.setattr(appmod, '_get_user_info', lambda cur, upn: ('Alice', 7, [11], False))
    monkeypatch.setattr(appmod, '_get_user_access', lambda cur, upn: ({'revenue': True}, None))
    monkeypatch.setattr(appmod, '_pbi_token', lambda: 'pbi-token')

    class FakeResp:
        def __init__(self, payload):
            self._p = payload
        def raise_for_status(self):
            pass
        def json(self):
            return self._p

    monkeypatch.setattr(appmod.requests, 'get',
                        lambda *a, **k: FakeResp({'embedUrl': 'https://embed', 'datasetId': 'ds1'}))
    monkeypatch.setattr(appmod.requests, 'post',
                        lambda *a, **k: FakeResp({'token': 'embed-token'}))

    r = client.get('/api/embed-token?report=revenue')
    assert r.status_code == 200
    j = r.get_json()
    assert j['token'] == 'embed-token'
    assert j['embedUrl'] == 'https://embed'


def test_embed_forbids_when_module_not_enabled(client, appmod, monkeypatch):
    # Provisioned tenant user, but the requested module isn't in their subscription.
    monkeypatch.setattr(appmod, '_auth', lambda: ('u@x.com', None))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: FakeConn())
    monkeypatch.setattr(appmod, '_get_user_info', lambda cur, upn: ('Alice', 7, [11], False))
    monkeypatch.setattr(appmod, '_get_user_access', lambda cur, upn: ({'revenue': False}, None))
    assert client.get('/api/embed-token?report=revenue').status_code == 403


# ── _get_user_access(): flags -> {section: bool}, practitioner ────────────────

def test_get_user_access_flags(appmod):
    # 10 access columns (order matches _ACCESS_COLUMNS) + Practitioner_Full_Name.
    row = (1, 0, 1, None, 1, 1, 0, 0, 0, 0, 'Dr Alice')
    access, pract = appmod._get_user_access(FakeCursor(one_row=row), 'alice@x.com')
    assert access['home'] is True
    assert access['revenue'] is False
    assert access['scheduling'] is False   # NULL -> False (fail-closed)
    assert access['nhs'] is True
    assert access['marketing'] is False
    assert pract == 'Dr Alice'


def test_get_user_access_no_row(appmod):
    access, pract = appmod._get_user_access(FakeCursor(one_row=None), 'nobody@x.com')
    assert all(v is False for v in access.values())
    assert pract is None


# ── Protected routes forbid unprovisioned users ───────────────────────────────

def _stub_unprovisioned(appmod, monkeypatch):
    monkeypatch.setattr(appmod, '_auth', lambda: ('u@x.com', None))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: FakeConn())
    monkeypatch.setattr(appmod, '_get_user_info', lambda cur, upn: (None, None, [], False))


def test_me_forbidden_when_unprovisioned(client, appmod, monkeypatch):
    _stub_unprovisioned(appmod, monkeypatch)
    assert client.get('/api/me').status_code == 403


def test_targets_get_forbidden_when_unprovisioned(client, appmod, monkeypatch):
    _stub_unprovisioned(appmod, monkeypatch)
    assert client.get('/api/targets').status_code == 403


# ── Manual-token onboarding: /api/onboarding/dentally/token ───────────────────

import time as _time


def _verified_token(appmod, email='p@x.com', practice='Acme Dental'):
    """A real HMAC-signed 'verified principal' token (same secret the app uses in tests)."""
    return appmod._sign_state({'t': 'verified', 'email': email, 'practice': practice, 'ts': _time.time()})


class _Resp:
    def __init__(self, status=200, payload=None):
        self.status_code = status
        self.ok = status < 400
        self._p = payload or {}
    def json(self):
        return self._p


def test_onboarding_token_requires_verified(client):
    r = client.post('/api/onboarding/dentally/token', json={'token': 'x' * 30, 'attested': True})
    assert r.status_code == 400


def test_onboarding_token_requires_attest(client, appmod):
    r = client.post('/api/onboarding/dentally/token',
                    json={'verified': _verified_token(appmod), 'token': 'x' * 30})
    assert r.status_code == 400


def test_onboarding_token_requires_token(client, appmod):
    r = client.post('/api/onboarding/dentally/token',
                    json={'verified': _verified_token(appmod), 'attested': True, 'token': 'short'})
    assert r.status_code == 400


def test_onboarding_token_rejects_bad_token(client, appmod, monkeypatch):
    # A clear 401 from Dentally = the pasted token is invalid -> block with the incorrect-key message.
    monkeypatch.setattr(appmod.requests, 'get', lambda *a, **k: _Resp(status=401))
    r = client.post('/api/onboarding/dentally/token',
                    json={'verified': _verified_token(appmod), 'attested': True, 'token': 'x' * 40})
    assert r.status_code == 400
    j = r.get_json()
    assert j['reason'] == 'invalid_token'
    assert 'token' in j['error'].lower()


def test_onboarding_token_reports_missing_permission(client, appmod, monkeypatch):
    # Valid token, but the financials endpoints 403 (financials:read not ticked). We must NOT store the
    # token; instead return the per-permission checklist so the practice can see what to enable.
    saved = {}
    monkeypatch.setattr(appmod, '_kv_set', lambda name, val: saved.update(name=name, val=val))
    monkeypatch.setattr(appmod, '_send_email', lambda *a, **k: True)

    def _get(url, *a, **k):
        fin = ('/invoices', '/invoice_items', '/payments', '/nhs_claims')
        return _Resp(status=403) if any(url.endswith(p) for p in fin) else _Resp(status=200)
    monkeypatch.setattr(appmod.requests, 'get', _get)

    r = client.post('/api/onboarding/dentally/token',
                    json={'verified': _verified_token(appmod), 'attested': True, 'token': 'x' * 40})
    assert r.status_code == 200
    j = r.get_json()
    assert j['ok'] is False and j['reason'] == 'missing_permissions'
    scopes = {g['scope']: g['ok'] for g in j['checks']}
    assert scopes['financials:read'] is False
    assert scopes['patient:read'] is True
    assert not saved   # nothing persisted -- we don't accept a token that can't read what we need


def test_onboarding_token_stores_and_notifies(client, appmod, monkeypatch):
    saved, notified = {}, {}
    monkeypatch.setattr(appmod.requests, 'get',
                        lambda *a, **k: _Resp(200, {'practices': [{'id': 99, 'name': 'Acme Dental'}]}))
    monkeypatch.setattr(appmod, '_kv_json', lambda name: {})
    monkeypatch.setattr(appmod, '_kv_set', lambda name, val: saved.update(name=name, val=val))
    monkeypatch.setattr(appmod, '_send_email',
                        lambda to, subj, body: notified.update(to=to, subj=subj, body=body) or True)

    r = client.post('/api/onboarding/dentally/token',
                    json={'verified': _verified_token(appmod), 'attested': True, 'token': 'tok' * 15})
    assert r.status_code == 200 and r.get_json()['ok'] is True

    import json as _json
    store = _json.loads(saved['val'])
    assert 'dentally:99' in store                        # keyed by the captured Dentally practice id
    e = store['dentally:99']
    assert e['personal_access_token'] == 'tok' * 15      # the secret is persisted to the store
    assert e['auth_method'] == 'personal_access_token'
    assert e['practice_name'] == 'Acme Dental'
    assert e['principal_email'] == 'p@x.com'
    assert e['status'] == 'pending_provision'
    assert notified['to'] == appmod.ONBOARDING_NOTIFY    # operator emailed that onboarding is pending
    assert 'Acme Dental' in notified['body']


def _stub_admin(appmod, monkeypatch, maintain=True):
    monkeypatch.setattr(appmod, '_auth', lambda: ('admin@x.com', None))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: FakeConn(FakeCursor(one_row=('Maple Dental',))))
    monkeypatch.setattr(appmod, '_get_user_info', lambda cur, upn: ('Admin', 100, [100], maintain))


def test_dentally_update_requires_auth(client):
    assert client.post('/api/dentally/token', json={'token': 'x' * 40}).status_code == 401


def test_dentally_update_requires_admin(client, appmod, monkeypatch):
    _stub_admin(appmod, monkeypatch, maintain=False)
    assert client.post('/api/dentally/token', json={'token': 'x' * 40}).status_code == 403


def test_dentally_update_rejects_bad_token(client, appmod, monkeypatch):
    _stub_admin(appmod, monkeypatch)
    monkeypatch.setattr(appmod.requests, 'get', lambda *a, **k: _Resp(401))
    monkeypatch.setattr(appmod, '_kv_json', lambda n: {})
    monkeypatch.setattr(appmod, '_kv_set', lambda n, v: None)
    r = client.post('/api/dentally/token', json={'token': 'x' * 40})
    assert r.status_code == 400 and r.get_json()['reason'] == 'invalid_token'


def test_dentally_update_missing_permission_not_saved(client, appmod, monkeypatch):
    saved = {}
    _stub_admin(appmod, monkeypatch)
    def _get(url, *a, **k):
        fin = ('/invoices', '/invoice_items', '/payments', '/nhs_claims')
        return _Resp(403) if any(url.endswith(p) for p in fin) else _Resp(200)
    monkeypatch.setattr(appmod.requests, 'get', _get)
    monkeypatch.setattr(appmod, '_kv_json', lambda n: {})
    monkeypatch.setattr(appmod, '_kv_set', lambda n, v: saved.update(v=v))
    r = client.post('/api/dentally/token', json={'token': 'x' * 40})
    j = r.get_json()
    assert r.status_code == 200 and j['ok'] is False and j['reason'] == 'missing_permissions'
    assert not saved   # a token that can't read everything is never written to the vault


def test_dentally_update_writes_token_when_good(client, appmod, monkeypatch):
    import json as _json
    saved = {}
    _stub_admin(appmod, monkeypatch)
    monkeypatch.setattr(appmod.requests, 'get', lambda *a, **k: _Resp(200))
    monkeypatch.setattr(appmod, '_kv_json',
                        lambda n: {'100': {'base_url': 'https://api.dentally.co/v1', 'name': 'Maple Dental', 'token': 'OLD'}})
    monkeypatch.setattr(appmod, '_kv_set', lambda n, v: saved.update(name=n, val=v))
    r = client.post('/api/dentally/token', json={'token': 'newtoken' * 6})
    assert r.status_code == 200 and r.get_json()['ok'] is True
    toks = _json.loads(saved['val'])
    assert toks['100']['token'] == 'newtoken' * 6         # updated in place
    assert toks['100']['base_url'] == 'https://api.dentally.co/v1'  # base_url preserved
    assert saved['name'] == f'dentally-tokens-{appmod.DENTALLY_ENV}'


def test_send_email_graph_primary(appmod, monkeypatch):
    calls = {}
    monkeypatch.setattr(appmod, 'APP_ENV', 'prod')   # transport test: not the non-prod redirect
    monkeypatch.setattr(appmod, 'GRAPH_SEND', True)
    monkeypatch.setattr(appmod, 'GRAPH_FROM', 'support@analytically.info')
    monkeypatch.setattr(appmod, '_graph_token', lambda: 'gtok')

    class _R:
        def raise_for_status(self): pass
    def _post(url, **kw):
        calls.update(url=url, json=kw.get('json'), auth=kw['headers']['Authorization'])
        return _R()
    monkeypatch.setattr(appmod.requests, 'post', _post)

    assert appmod._send_email('craig@x.com', 'Subj', 'Body', reply_to='support@analytically.info') is True
    assert calls['url'].endswith('/users/support@analytically.info/sendMail')
    msg = calls['json']['message']
    assert msg['toRecipients'][0]['emailAddress']['address'] == 'craig@x.com'
    assert msg['replyTo'][0]['emailAddress']['address'] == 'support@analytically.info'
    assert calls['auth'] == 'Bearer gtok'


def test_send_email_graph_sender_override(appmod, monkeypatch):
    calls = {}
    monkeypatch.setattr(appmod, 'GRAPH_SEND', True)
    monkeypatch.setattr(appmod, '_graph_token', lambda: 'gtok')
    class _R:
        def raise_for_status(self): pass
    monkeypatch.setattr(appmod.requests, 'post', lambda url, **kw: calls.update(url=url) or _R())
    appmod._send_email('x@y.com', 'S', 'B', sender='sales@analytically.info')
    assert calls['url'].endswith('/users/sales@analytically.info/sendMail')


def test_send_email_graph_falls_back(appmod, monkeypatch):
    # Graph errors (e.g. Mail.Send not consented yet) -> must NOT raise; with no ACS/SMTP in test env
    # it falls through to the log path and returns False.
    def _boom():
        raise RuntimeError('no consent')
    monkeypatch.setattr(appmod, 'GRAPH_SEND', True)
    monkeypatch.setattr(appmod, '_graph_token', _boom)
    monkeypatch.setattr(appmod, '_kv_get', lambda n: None)
    assert appmod._send_email('x@y.com', 'S', 'B') is False


def _stub_status(appmod, monkeypatch, kv):
    monkeypatch.setattr(appmod, '_auth', lambda: ('admin@x.com', None))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: FakeConn())
    monkeypatch.setattr(appmod, '_get_user_info', lambda cur, upn: ('Admin', 100, [100], True))
    monkeypatch.setattr(appmod, '_kv_json', lambda n: kv)


def test_dentally_status_ok(client, appmod, monkeypatch):
    _stub_status(appmod, monkeypatch, {'100': {'token': 'tok', 'base_url': 'https://api.dentally.co/v1'}})
    monkeypatch.setattr(appmod.requests, 'get', lambda *a, **k: _Resp(200))
    assert client.get('/api/dentally/status').get_json()['status'] == 'ok'


def test_dentally_status_invalid(client, appmod, monkeypatch):
    # token present but Dentally rejects it -> 'invalid' (the bug the user hit: it must NOT say connected)
    _stub_status(appmod, monkeypatch, {'100': {'token': 'tok'}})
    monkeypatch.setattr(appmod.requests, 'get', lambda *a, **k: _Resp(401))
    assert client.get('/api/dentally/status').get_json()['status'] == 'invalid'


def test_dentally_status_missing(client, appmod, monkeypatch):
    _stub_status(appmod, monkeypatch, {})
    monkeypatch.setattr(appmod.requests, 'get', lambda *a, **k: _Resp(200))
    assert client.get('/api/dentally/status').get_json()['status'] == 'missing'


# ── Warehouse health monitor: /api/monitor/health ────────────────────────────

class _MonCursor:
    # health rows are (Tenant_ID, last_401, last_ok); last_* are comparable (ISO strings or None).
    # last_report is the previous MONITOR row's Logged_At (a datetime) -- None means "never reported",
    # which makes the handler fall back to the rolling window.
    def __init__(self, proc, ing, health=None, last_report=None):
        self._proc, self._ing, self._health, self._which = proc, ing, (health or []), None
        self._last_report = last_report
    def execute(self, sql, *a):
        if "Phase IN ('MONITOR'" in sql:    self._which = 'watermark'
        elif 'Process_Execution_Log' in sql: self._which = 'proc'
        elif 'GROUP BY Tenant_ID' in sql:   self._which = 'health'
        else:                               self._which = 'ing'
        return self
    def fetchone(self):
        return (self._last_report,) if self._which == 'watermark' else None
    def fetchall(self):
        return {'proc': self._proc, 'ing': self._ing, 'health': self._health}[self._which]


class _MonConn:
    def __init__(self, cur):
        self._cur = cur
    def cursor(self):
        return self._cur
    def close(self):
        pass


def test_monitor_requires_key(client, appmod, monkeypatch):
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    assert client.post('/api/monitor/health').status_code == 401
    assert client.post('/api/monitor/health', headers={'X-Monitor-Key': 'wrong'}).status_code == 401


def test_monitor_no_failures_no_email(client, appmod, monkeypatch):
    sent = {}
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _MonConn(_MonCursor([], [])))
    monkeypatch.setattr(appmod, '_send_email', lambda *a, **k: sent.update(x=1))
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    assert j['failures'] == 0 and not sent


def test_monitor_dev_detects_but_suppresses_emails(client, appmod, monkeypatch):
    # APP_ENV is 'test' (conftest) -> detection happens but NO emails are sent from a non-prod app.
    sent = []
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    monkeypatch.setattr(appmod, '_tenant_primary_email', lambda tid: 'craig@x.com')
    proc = [('2026-09-01 06:00', 'Audit.Orchestrate_Build', 'boom')]
    ing = [('2026-09-01 15:04', 100, 'patients', 'SKIP', '401 Client Error: Unauthorized for url: x'),
           ('2026-09-01 15:04', 100, 'invoices', 'SKIP', '401 Client Error: Unauthorized for url: y')]
    health = [(100, '2026-09-01 15:04', None)]   # a 401 with no later Dentally success -> unresolved
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _MonConn(_MonCursor(proc, ing, health)))
    monkeypatch.setattr(appmod, '_send_email', lambda *a, **k: sent.append(a))
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    assert j['process_failures'] == 1 and j['ingest_failures'] == 2
    assert j['bad_token_tenants'] == [100] and j['emails_enabled'] is False
    assert not sent   # non-prod NEVER emails


def test_monitor_prod_emails_operator_and_single_main_account(client, appmod, monkeypatch):
    sent = []
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    monkeypatch.setattr(appmod, 'APP_ENV', 'prod')
    monkeypatch.setattr(appmod, '_tenant_primary_email', lambda tid: 'craig@mapledental.co.uk')
    # two 401 rows for the same tenant -> still ONE customer email (to the main account)
    ing = [('2026-09-01 15:04', 100, 'patients', 'SKIP', '401 Client Error: Unauthorized for url: x'),
           ('2026-09-01 15:04', 100, 'invoices', 'SKIP', '401 Client Error: Unauthorized for url: y')]
    health = [(100, '2026-09-01 15:04', None)]   # unresolved: no Dentally success after the 401
    monkeypatch.setattr(appmod, '_kv_json', lambda n: {})     # no prior nudge -> cooldown clear
    monkeypatch.setattr(appmod, '_kv_set', lambda n, v: None)
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _MonConn(_MonCursor([], ing, health)))
    monkeypatch.setattr(appmod, '_send_email', lambda to, subj, body, **kw: sent.append((to, subj, body, kw)))
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    assert j['emails_enabled'] is True and j['principals_notified'] == 1 and j['bad_token_tenants'] == [100]
    tos = [s[0] for s in sent]
    assert appmod.MONITOR_NOTIFY in tos                       # operator summary
    assert tos.count('craig@mapledental.co.uk') == 1          # exactly ONE nudge to the main account
    nudge = next(s for s in sent if s[0] == 'craig@mapledental.co.uk')
    assert nudge[3].get('reply_to') == appmod.SUPPORT_FROM    # Reply-To = Support@ (interim option B)
    assert nudge[3].get('sender') is None                    # sent from the deliverable managed domain
    assert 'settings=dentally' in nudge[2] and 'Personal Access Token' in nudge[2]


def test_monitor_resolved_token_no_nudge(client, appmod, monkeypatch):
    # 401s still sit in the window, but a later Dentally FETCH means the token was FIXED -> no nudge,
    # and with nothing else actionable, no operator summary either. This is the "stop nagging" guarantee.
    sent = []
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    monkeypatch.setattr(appmod, 'APP_ENV', 'prod')
    monkeypatch.setattr(appmod, '_tenant_primary_email', lambda tid: 'craig@mapledental.co.uk')
    ing = [('2026-09-01 15:04', 100, 'patients', 'SKIP', '401 Client Error: Unauthorized for url: x')]
    health = [(100, '2026-09-01 15:04', '2026-09-01 16:10')]   # success AFTER the 401 -> resolved
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _MonConn(_MonCursor([], ing, health)))
    monkeypatch.setattr(appmod, '_send_email', lambda to, subj, body, **kw: sent.append((to, subj, body, kw)))
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    assert j['bad_token_tenants'] == [] and j['principals_notified'] == 0
    assert not sent   # nothing actionable -> no nudge AND no operator summary


def test_monitor_resolved_401_absent_from_summary(client, appmod, monkeypatch):
    # The 2026-09-08 regression: a tenant whose token was fixed yesterday still appeared as a
    # connection failure because the body was built from the RAW rows. Here something else IS
    # actionable (a process failure), so the operator summary goes out -- but the resolved 401 must
    # not be counted in it or named in it.
    sent = []
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    monkeypatch.setattr(appmod, 'APP_ENV', 'prod')
    monkeypatch.setattr(appmod, '_tenant_primary_email', lambda tid: 'craig@mapledental.co.uk')
    proc = [('2026-09-08 21:24', 'Audit.Orchestrate_Build', 'xero step blew up')]
    ing = [('2026-09-07 21:22', 100, 'patients', 'SKIP', '401 Client Error: Unauthorized for url: x'),
           ('2026-09-07 21:22', 100, 'invoices', 'SKIP', '401 Client Error: Unauthorized for url: y')]
    health = [(100, '2026-09-07 21:22', '2026-09-08 21:30')]   # success AFTER the 401 -> resolved
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _MonConn(_MonCursor(proc, ing, health)))
    monkeypatch.setattr(appmod, '_send_email', lambda to, subj, body, **kw: sent.append((to, subj, body)))
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    assert j['bad_token_tenants'] == [] and j['principals_notified'] == 0
    assert j['ingest_failures'] == 0 and j['resolved_401_suppressed'] == 2
    assert j['failures'] == 1                        # the process failure only
    body = next(s[2] for s in sent if s[0] == appmod.MONITOR_NOTIFY)
    assert 'tenant 100' not in body and 'Unauthorized' not in body
    assert 'xero step blew up' in body               # the real error is still reported


def test_monitor_unresolved_401_still_reported(client, appmod, monkeypatch):
    # Mirror image: the token is genuinely still broken, so the 401s ARE real errors and must survive
    # the filter -- otherwise the fix above would blind the summary to live outages.
    sent = []
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    monkeypatch.setattr(appmod, 'APP_ENV', 'prod')
    monkeypatch.setattr(appmod, '_tenant_primary_email', lambda tid: 'craig@mapledental.co.uk')
    monkeypatch.setattr(appmod, '_kv_json', lambda n: {})
    monkeypatch.setattr(appmod, '_kv_set', lambda n, v: None)
    ing = [('2026-09-07 21:22', 100, 'patients', 'SKIP', '401 Client Error: Unauthorized for url: x')]
    health = [(100, '2026-09-07 21:22', None)]                 # no success after the 401 -> broken
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _MonConn(_MonCursor([], ing, health)))
    monkeypatch.setattr(appmod, '_send_email', lambda to, subj, body, **kw: sent.append((to, subj, body)))
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    assert j['bad_token_tenants'] == [100]
    assert j['ingest_failures'] == 1 and j['resolved_401_suppressed'] == 0
    body = next(s[2] for s in sent if s[0] == appmod.MONITOR_NOTIFY)
    assert 'tenant 100' in body


def test_monitor_untenanted_401_not_suppressed(client, appmod, monkeypatch):
    # A 401 with no Tenant_ID cannot be attributed to a practice token, so nothing proves it fixed --
    # it must survive the resolved filter rather than being silently swallowed.
    sent = []
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    monkeypatch.setattr(appmod, 'APP_ENV', 'prod')
    ing = [('2026-09-08 21:24', None, 'Orchestrate_Build', 'FAILED', '401 Unauthorized calling the warehouse')]
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _MonConn(_MonCursor([], ing, [])))
    monkeypatch.setattr(appmod, '_send_email', lambda to, subj, body, **kw: sent.append((to, subj, body)))
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    assert j['ingest_failures'] == 1 and j['resolved_401_suppressed'] == 0
    assert sent, 'an untenanted 401 is actionable and must be emailed'


def test_monitor_reports_only_since_last_report(client, appmod, monkeypatch):
    # The report window starts at the previous MONITOR row, so a run's failures are emailed once and
    # never re-listed by the next night's run.
    from datetime import datetime, timedelta
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    watermark = datetime.utcnow() - timedelta(hours=20)
    monkeypatch.setattr(appmod, '_fabric_conn',
                        lambda *a, **k: _MonConn(_MonCursor([], [], last_report=watermark)))
    monkeypatch.setattr(appmod, '_send_email', lambda *a, **k: None)
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    assert j['report_since'] == watermark.strftime('%Y-%m-%dT%H:%M:%S')


def test_monitor_report_window_capped_when_watermark_ancient(client, appmod, monkeypatch):
    # A stale watermark (monitor offline for weeks, log trimmed) must not dump a month of backlog
    # into one email -- the reach is capped.
    from datetime import datetime, timedelta
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    monkeypatch.setattr(appmod, 'MONITOR_REPORT_MAX_HOURS', 168)
    ancient = datetime.utcnow() - timedelta(days=40)
    monkeypatch.setattr(appmod, '_fabric_conn',
                        lambda *a, **k: _MonConn(_MonCursor([], [], last_report=ancient)))
    monkeypatch.setattr(appmod, '_send_email', lambda *a, **k: None)
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    reported = datetime.strptime(j['report_since'], '%Y-%m-%dT%H:%M:%S')
    expected = datetime.utcnow() - timedelta(hours=168)
    assert abs((reported - expected).total_seconds()) < 120
    assert reported > ancient


def test_monitor_nudge_cooldown_suppresses_repeat(client, appmod, monkeypatch):
    # Token still broken, but this tenant was nudged moments ago -> the per-tenant cooldown suppresses
    # a second customer email (the manual-trigger + delayed-cron double). Operator summary still goes.
    from datetime import datetime
    sent = []
    monkeypatch.setattr(appmod, 'MONITOR_KEY', 'secret')
    monkeypatch.setattr(appmod, 'APP_ENV', 'prod')
    monkeypatch.setattr(appmod, '_tenant_primary_email', lambda tid: 'craig@mapledental.co.uk')
    ing = [('2026-09-01 15:04', 100, 'patients', 'SKIP', '401 Client Error: Unauthorized for url: x')]
    health = [(100, '2026-09-01 15:04', None)]                      # still broken
    monkeypatch.setattr(appmod, '_kv_json', lambda n: {'100': datetime.utcnow().isoformat()})  # nudged just now
    saved = {}
    monkeypatch.setattr(appmod, '_kv_set', lambda n, v: saved.update(v=v))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _MonConn(_MonCursor([], ing, health)))
    monkeypatch.setattr(appmod, '_send_email', lambda to, subj, body, **kw: sent.append((to, subj)))
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    assert j['bad_token_tenants'] == [100] and j['principals_notified'] == 0   # cooldown held the nudge
    tos = [s[0] for s in sent]
    assert 'craig@mapledental.co.uk' not in tos                    # NO second customer email
    assert appmod.MONITOR_NOTIFY in tos                            # operator still informed
    assert not saved                                               # state not rewritten (nothing sent)


def test_onboarding_token_records_on_network_blip(client, appmod, monkeypatch):
    # A transient error validating the token must NOT lose a verified signup -- record under the email key.
    def _boom(*a, **k):
        raise appmod.requests.RequestException('down')
    monkeypatch.setattr(appmod.requests, 'get', _boom)
    monkeypatch.setattr(appmod, '_kv_json', lambda name: {})
    monkeypatch.setattr(appmod, '_kv_set', lambda name, val: None)
    monkeypatch.setattr(appmod, '_send_email', lambda *a, **k: True)
    r = client.post('/api/onboarding/dentally/token',
                    json={'verified': _verified_token(appmod), 'attested': True, 'token': 'x' * 40})
    assert r.status_code == 200 and r.get_json()['ok'] is True


# ── "Stop using Analytically": /api/cancel ────────────────────────────────────

class _RecCursor:
    """Records every statement, and answers fetches by matching on the SQL text."""
    def __init__(self, answers, rowcount=1):
        self.answers, self.sql, self._last = answers, [], ''
        # Code that branches on whether an UPDATE hit anything (UPDATE-then-INSERT upserts)
        # needs this; default 1 = the row was already there.
        self.rowcount = rowcount

    def execute(self, sql, *a):
        self._last = sql
        self.sql.append((sql, a[0] if a else None))
        return self

    def _answer(self):
        for frag, val in self.answers.items():
            if frag in self._last:
                return val
        return None

    def fetchone(self):
        v = self._answer()
        return v[0] if isinstance(v, list) and v else v

    def fetchall(self):
        v = self._answer()
        return v if isinstance(v, list) else []

    def ran(self, frag):
        return [s for s, _ in self.sql if frag in s]


class _RecConn:
    def __init__(self, cur):
        self._cur = cur
    def cursor(self):
        return self._cur
    def close(self):
        pass


def _cancel_env(appmod, monkeypatch, primary='owner@practice.co.uk', users=None, tids=(11,)):
    """Wire both connections + auth for the cancel endpoint. Returns (wh_cursor, appdb_cursor, sent)."""
    users = ['owner@practice.co.uk', 'nurse@practice.co.uk'] if users is None else users
    wh = _RecCursor({
        'Tenant_Name': [('Maple Dental',)],
        'SELECT Tenant_ID, Client_ID': [(t, 700 + t) for t in tids],
        'COUNT(*) FROM Billing.Account_Billing': [(1,)],
    })
    ap = _RecCursor({
        'Primary_Email': [(primary,)] if primary else [],
        'SELECT User_UPN': [(u,) for u in users],
    })
    sent = []
    monkeypatch.setattr(appmod, '_auth', lambda: ('owner@practice.co.uk', None))
    monkeypatch.setattr(appmod, '_get_user_info', lambda c, u: ('Owner', 7, list(tids), True))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _RecConn(wh))
    monkeypatch.setattr(appmod, '_appdb_conn', lambda *a, **k: _RecConn(ap))
    monkeypatch.setattr(appmod, '_send_email', lambda to, subj, body, **kw: sent.append((to, subj, body)))
    return wh, ap, sent


def test_cancel_refuses_non_primary(client, appmod, monkeypatch):
    # A practice ADMIN who is not the billing owner must not be able to end the subscription:
    # it cuts off everyone, so it is the lead account's call alone.
    wh, ap, sent = _cancel_env(appmod, monkeypatch, primary='someoneelse@practice.co.uk')
    r = client.post('/api/cancel', json={'reason': 'Too expensive'})
    assert r.status_code == 403
    assert 'primary account holder' in r.get_json()['error']
    assert not ap.ran('UPDATE Input.Application_Users')   # nothing revoked
    assert not wh.ran('UPDATE Audit.Tenants')             # tenant untouched
    assert not sent


def test_cancel_refuses_when_no_primary_recorded(client, appmod, monkeypatch):
    # A blank billing contact must not become a loophole that lets any admin terminate.
    wh, ap, sent = _cancel_env(appmod, monkeypatch, primary=None)
    r = client.post('/api/cancel', json={'reason': 'x'})
    assert r.status_code == 403
    assert 'No primary account holder' in r.get_json()['error']
    assert not ap.ran('UPDATE Input.Application_Users') and not sent


def test_cancel_by_primary_revokes_everyone_and_alerts_sales(client, appmod, monkeypatch):
    wh, ap, sent = _cancel_env(appmod, monkeypatch)
    r = client.post('/api/cancel', json={'reason': 'Closing the practice'})
    assert r.status_code == 200 and r.get_json()['users_revoked'] == 2

    upd = ap.ran('UPDATE Input.Application_Users')
    assert len(upd) == 1
    # every module flag cleared, admin dropped, profile recorded -- and the ROW KEPT, because
    # usp_Generate_Invoice_Lines draws its user list from Application_Users and a DELETE would
    # lose the final month's invoice.
    for col in appmod._ALL_MODULE_COLS:
        assert f'{col} = 0' in upd[0]
    assert "Profile_Key = 'no_access'" in upd[0] and 'Maintain_Targets = 0' in upd[0]
    assert not ap.ran('DELETE FROM Input.Application_Users')
    # one Access_Log row per user losing access (this is what closes the billable interval)
    assert len(ap.ran('INSERT INTO Input.Access_Log')) == 2
    # tenant deactivated -> ingest stops and auth fails closed before the sync catches up
    assert wh.ran('UPDATE Audit.Tenants')
    # nothing scheduled for deletion by machine: Delete_By is a marker for the support team
    assert wh.ran('Delete_By')
    to, subj, body = sent[0]
    assert to == 'Sales@Analytically.info'
    assert 'Maple Dental' in subj and 'Closing the practice' in body
    assert 'no data has been deleted' in body


def test_cancel_bills_the_current_month(client, appmod, monkeypatch):
    # Cancelled_At must be the START OF NEXT MONTH. usp_Generate_Invoice_Lines bills a month only
    # when `Cancelled_At > @MEnd`, so stamping it with now() would silently drop the final month.
    wh, ap, sent = _cancel_env(appmod, monkeypatch)
    client.post('/api/cancel', json={'reason': 'x'})
    billing = ' '.join(wh.ran('Billing.Account_Billing'))
    assert 'DATEADD(month, 1, DATEFROMPARTS' in billing
    assert 'Cancelled_At = SYSUTCDATETIME()' not in billing


def test_cancel_survives_a_failing_alert_email(client, appmod, monkeypatch):
    # The termination is already committed when the mail is sent; a mail failure must not 500 the
    # caller into believing it did not happen.
    wh, ap, sent = _cancel_env(appmod, monkeypatch)
    def boom(*a, **k):
        raise RuntimeError('graph down')
    monkeypatch.setattr(appmod, '_send_email', boom)
    r = client.post('/api/cancel', json={'reason': 'x'})
    assert r.status_code == 200 and r.get_json()['ok'] is True
    assert ap.ran('UPDATE Input.Application_Users')


# ── Primary account holder handover (save_team) ───────────────────────────────

def _team_env(appmod, monkeypatch, previous_primary):
    """Wire save_team with an existing (or absent) primary. Returns (appdb_cursor, sent)."""
    wh = _RecCursor({
        'SELECT Tenant_ID, Client_ID': [(11, 711)],
        'Dim_Practitioners': [],
    })
    ap = _RecCursor({
        'SELECT Primary_Email': [(previous_primary,)] if previous_primary else [],
        'SELECT LOWER(User_UPN)': [],
    })
    sent = []
    monkeypatch.setattr(appmod, '_auth', lambda: ('newboss@practice.co.uk', None))
    monkeypatch.setattr(appmod, '_get_user_info', lambda c, u: ('New Boss', 7, [11], True))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _RecConn(wh))
    monkeypatch.setattr(appmod, '_appdb_conn', lambda *a, **k: _RecConn(ap))
    monkeypatch.setattr(appmod, '_send_email', lambda to, subj, body, **kw: sent.append((to, subj, body)))
    return ap, sent


def test_primary_handover_notifies_outgoing_and_sales(client, appmod, monkeypatch):
    # Any admin may take the primary over -- that is the continuity path when the primary is off
    # sick or has left. It must never be SILENT: the person losing it and Sales@ are both told.
    ap, sent = _team_env(appmod, monkeypatch, 'oldboss@practice.co.uk')
    r = client.post('/api/team', json={'rows': [], 'primary_email': 'newboss@practice.co.uk',
                                       'invoice_email': ''})
    assert r.status_code == 200
    # exactly one notice, to the person losing the role -- Sales@ is not copied on a handover
    assert [s[0] for s in sent] == ['oldboss@practice.co.uk']
    body = sent[0][2]
    assert 'oldboss@practice.co.uk' in body and 'newboss@practice.co.uk' in body
    assert 'newboss@practice.co.uk' in body   # who did it is on the record
    # a handover the recipient did not expect is a SUPPORT matter, not a sales one
    assert appmod.SUPPORT_FROM in body
    assert 'sales@analytically.info' not in body.lower()


def test_primary_first_time_setup_notifies_nobody(client, appmod, monkeypatch):
    # Bootstrap: a tenant with no primary recorded (dev today) must be able to get one, and there
    # is nobody to notify about a handover that did not happen.
    ap, sent = _team_env(appmod, monkeypatch, None)
    r = client.post('/api/team', json={'rows': [], 'primary_email': 'firstboss@practice.co.uk',
                                       'invoice_email': ''})
    assert r.status_code == 200
    assert not sent
    assert ap.ran('INSERT INTO Input.Billing_Contact')   # but it WAS set


def test_primary_unchanged_is_not_a_handover(client, appmod, monkeypatch):
    # Re-saving the subscriptions screen keeps sending primary_email; that is not a takeover and
    # must not fire a notice every time someone edits the team.
    ap, sent = _team_env(appmod, monkeypatch, 'Boss@Practice.co.uk')
    r = client.post('/api/team', json={'rows': [], 'primary_email': 'boss@practice.co.uk',
                                       'invoice_email': ''})
    assert r.status_code == 200
    assert not sent   # case-insensitive compare


def test_primary_handover_survives_failing_notice(client, appmod, monkeypatch):
    # The change is already saved; a mail failure must not roll it back or 500 the caller.
    ap, sent = _team_env(appmod, monkeypatch, 'oldboss@practice.co.uk')
    def boom(*a, **k):
        raise RuntimeError('graph down')
    monkeypatch.setattr(appmod, '_send_email', boom)
    r = client.post('/api/team', json={'rows': [], 'primary_email': 'newboss@practice.co.uk',
                                       'invoice_email': ''})
    assert r.status_code == 200
    assert ap.ran('INSERT INTO Input.Billing_Contact')


def test_cancel_leaves_support_logins_alone(client, appmod, monkeypatch):
    """Our own @analytically.info logins are not the practice's users.

    They are inserted straight into Application_Users by SQL (no Dentally user, so they never show
    on the subscriptions roster), usp_Generate_Invoice_Lines already excludes them from billing on
    the same test, and support must keep access to run the re-engagement call and the eventual
    manual cleanup. Revoking them would lock the vendor out of a tenant that still holds data.
    """
    wh, ap, sent = _cancel_env(appmod, monkeypatch)
    client.post('/api/cancel', json={'reason': 'x'})
    sql = ' '.join(ap.ran('Input.Application_Users'))
    assert "LOWER(User_UPN) NOT LIKE '%@analytically.info'" in sql
    # and it guards the UPDATE, not just the SELECT that counts who lost access
    upd = ap.ran('UPDATE Input.Application_Users')[0]
    assert "NOT LIKE '%@analytically.info'" in upd


# ── Non-prod mail redirect ────────────────────────────────────────────────────

def _graph_capture(appmod, monkeypatch):
    """Intercept the Graph send and hand back the message payload it would have posted."""
    calls = {}
    monkeypatch.setattr(appmod, 'GRAPH_SEND', True)
    monkeypatch.setattr(appmod, 'GRAPH_FROM', 'support@analytically.info')
    monkeypatch.setattr(appmod, '_graph_token', lambda: 'gtok')

    class _R:
        def raise_for_status(self):
            pass

    def _post(url, **kw):
        calls['json'] = kw.get('json')
        return _R()

    monkeypatch.setattr(appmod.requests, 'post', _post)
    return calls


def test_non_prod_mail_is_redirected_to_support(appmod, monkeypatch):
    """Dev carries prod's GRAPH_SEND config, and dev's tenant 100 is a copy of a live practice, so
    its stored addresses are real. A test nudge/handover/termination must not reach the practice."""
    monkeypatch.setattr(appmod, 'APP_ENV', 'dev')
    calls = _graph_capture(appmod, monkeypatch)
    appmod._send_email('craigjack@mapledental.co.uk', 'Your data has stopped updating', 'body text')
    msg = calls['json']['message']
    assert msg['toRecipients'][0]['emailAddress']['address'] == appmod.MAIL_REDIRECT
    # the real recipient is still legible, so the test remains meaningful
    assert 'craigjack@mapledental.co.uk' in msg['subject']
    assert 'craigjack@mapledental.co.uk' in msg['body']['content']
    assert msg['subject'].startswith('[DEV -> ')


def test_prod_mail_reaches_the_real_recipient(appmod, monkeypatch):
    monkeypatch.setattr(appmod, 'APP_ENV', 'prod')
    calls = _graph_capture(appmod, monkeypatch)
    appmod._send_email('craigjack@mapledental.co.uk', 'Subject', 'body')
    msg = calls['json']['message']
    assert msg['toRecipients'][0]['emailAddress']['address'] == 'craigjack@mapledental.co.uk'
    assert msg['subject'] == 'Subject'


def test_cancel_allowed_for_support_account_without_a_primary(client, appmod, monkeypatch):
    """Support can always end a subscription, including on a tenant with no primary recorded.

    A support login can never be the primary — that is a radio over the Dentally roster and support
    has no Dentally user — so gating purely on the primary would lock the vendor out of acting on
    the practice's behalf (phone request, or the primary has left and the mailbox is unreachable).
    """
    wh, ap, sent = _cancel_env(appmod, monkeypatch, primary=None)
    monkeypatch.setattr(appmod, '_auth', lambda: ('admin@analytically.info', None))
    r = client.post('/api/cancel', json={'reason': 'Requested by phone'})
    assert r.status_code == 200
    assert ap.ran('UPDATE Input.Application_Users')
    assert sent and sent[0][0] == 'Sales@Analytically.info'


def test_cancel_still_refuses_a_non_primary_practice_admin(client, appmod, monkeypatch):
    """The support exemption must not leak to practice users: only @analytically.info bypasses."""
    wh, ap, sent = _cancel_env(appmod, monkeypatch, primary='owner@practice.co.uk')
    monkeypatch.setattr(appmod, '_auth', lambda: ('nurse@practice.co.uk', None))
    r = client.post('/api/cancel', json={'reason': 'x'})
    assert r.status_code == 403
    assert not ap.ran('UPDATE Input.Application_Users') and not sent


def test_app_env_defaults_to_non_prod(appmod, monkeypatch):
    """An unconfigured APP_ENV must mean "not prod", so mail fails safe.

    APP_ENV gates both the monitor's customer nudges and the _send_email redirect. It used to
    default to 'prod', which made dev safe only while its APP_ENV variable survived -- and dev
    carries prod's Graph config plus a copy of a live practice's addresses.
    """
    import importlib, os as _os
    saved = _os.environ.pop('APP_ENV', None)
    try:
        mod = importlib.reload(appmod)
        assert mod.APP_ENV != 'prod'
    finally:
        if saved is not None:
            _os.environ['APP_ENV'] = saved
        importlib.reload(appmod)


# ── Stripe: the payment rail ──────────────────────────────────────────────────
# The key-prefix guard is the one that matters most here. Everything else in this file
# fails visibly; a dev deployment holding a live key fails by charging a real dentist.


class _FakeObj:
    """Stand-in for a Stripe resource.

    Deliberately NOT a dict subclass. Real stripe>=15 resources are not dicts and have no
    .get() -- calling it raises AttributeError. A dict-based double made `cust.get(...)` look
    fine in tests while the endpoint would have thrown on the first real call, so this double
    exposes attributes only.
    """
    def __init__(self, **kw):
        self.__dict__.update(kw)


def _card(pm_id, last4='4242', brand='visa'):
    return _FakeObj(id=pm_id, card=_FakeObj(brand=brand, last4=last4, exp_month=4, exp_year=2030))


def _fake_stripe(calls, default_pm='pm_DEFAULT', cards=None):
    """Minimal stand-in for the stripe module: records what would have been sent.

    `default_pm=None` with `cards` non-empty models the state Checkout actually leaves behind --
    the card is ATTACHED to the customer but is not the default payment method. That is the exact
    condition that put "Card saved." and "No card on file." on screen together, so the double has
    to be able to reproduce it.
    """
    cards = [_card('pm_DEFAULT')] if cards is None else cards

    class _Customer:
        @staticmethod
        def create(**kw):
            calls.append(('customer.create', kw))
            return _FakeObj(id='cus_TEST123')

        @staticmethod
        def retrieve(cid, **kw):
            calls.append(('customer.retrieve', cid))
            pm = next((c for c in cards if c.id == default_pm), None)
            return _FakeObj(invoice_settings=_FakeObj(default_payment_method=pm))

        @staticmethod
        def modify(cid, **kw):
            calls.append(('customer.modify', (cid, kw)))
            return _FakeObj(id=cid)

    class _PaymentMethod:
        @staticmethod
        def list(**kw):
            calls.append(('pm.list', kw))
            return _FakeObj(data=list(cards))          # Stripe returns newest first

        @staticmethod
        def detach(pm_id, **kw):
            calls.append(('pm.detach', pm_id))
            return _FakeObj(id=pm_id)

    class _Session:
        @staticmethod
        def create(**kw):
            calls.append(('session.create', kw))
            return _FakeObj(id='cs_TEST', url='https://checkout.stripe.com/c/pay/cs_TEST')

    return _FakeObj(Customer=_Customer, PaymentMethod=_PaymentMethod,
                    checkout=_FakeObj(Session=_Session))


def _stripe_env(appmod, monkeypatch, primary='owner@practice.co.uk', customer_id=None,
                caller='owner@practice.co.uk', tids=(11,), default_pm='pm_DEFAULT', cards=None):
    """Wire both connections, auth and a fake Stripe. Returns (wh_cursor, appdb_cursor, calls)."""
    wh = _RecCursor({
        'Stripe_Customer_ID FROM Billing.Account_Billing': [(customer_id,)] if customer_id else [(None,)],
        'Tenant_Name': [('Maple Dental',)],
    })
    ap = _RecCursor({'Primary_Email': [(primary,)] if primary else []})
    calls = []
    monkeypatch.setattr(appmod, '_auth', lambda: (caller, None))
    monkeypatch.setattr(appmod, '_get_user_info', lambda c, u: ('Owner', 7, list(tids), True))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _RecConn(wh))
    monkeypatch.setattr(appmod, '_appdb_conn', lambda *a, **k: _RecConn(ap))
    monkeypatch.setattr(appmod, '_tenant_primary_email', lambda tid: primary)
    monkeypatch.setattr(appmod, '_stripe', lambda: _fake_stripe(calls, default_pm, cards))
    return wh, ap, calls


def test_stripe_refuses_a_live_key_outside_prod(appmod, monkeypatch):
    # The guard that stops a dev deployment charging real cards. A live key reaching dev is a
    # paste error, and the only safe response is to refuse loudly rather than transact.
    appmod._stripe_singleton = None
    monkeypatch.setattr(appmod, 'STRIPE_ENV', 'dev')
    monkeypatch.setattr(appmod, '_kv_get', lambda n, d=None: 'sk_live_realmoney')
    try:
        appmod._stripe()
        assert False, 'a live key must not be accepted in dev'
    except RuntimeError as e:
        assert 'sk_test_' in str(e) and 'dev' in str(e)
    finally:
        appmod._stripe_singleton = None


def test_stripe_refuses_a_test_key_in_prod(appmod, monkeypatch):
    # The mirror image, and just as bad: prod holding a test key takes no money at all while
    # every invoice appears to succeed.
    appmod._stripe_singleton = None
    monkeypatch.setattr(appmod, 'STRIPE_ENV', 'prod')
    monkeypatch.setattr(appmod, '_kv_get', lambda n, d=None: 'sk_test_pretend')
    try:
        appmod._stripe()
        assert False, 'a test key must not be accepted in prod'
    except RuntimeError as e:
        assert 'sk_live_' in str(e)
    finally:
        appmod._stripe_singleton = None


def test_stripe_refuses_when_no_key_is_set(appmod, monkeypatch):
    # An unset secret must not fall through to an unauthenticated client.
    appmod._stripe_singleton = None
    monkeypatch.setattr(appmod, 'STRIPE_ENV', 'dev')
    monkeypatch.setattr(appmod, '_kv_get', lambda n, d=None: None)
    try:
        appmod._stripe()
        assert False, 'a missing key must raise'
    except RuntimeError as e:
        assert 'stripe-secret-key-dev' in str(e)
    finally:
        appmod._stripe_singleton = None


def test_setup_session_refuses_non_primary(client, appmod, monkeypatch):
    # Saving a card commits the practice to being charged, so it is the billing owner's call --
    # the same gate as ending the subscription, and now literally the same function.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, primary='someoneelse@practice.co.uk')
    r = client.post('/api/stripe/setup-session', json={})
    assert r.status_code == 403
    assert 'primary account holder' in r.get_json()['error']
    assert not calls                                   # nothing reached Stripe
    assert not wh.ran('UPDATE Billing.Account_Billing')  # no customer created


def test_setup_session_refuses_when_no_primary_recorded(client, appmod, monkeypatch):
    # A blank billing contact must not become a loophole here either.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, primary=None)
    r = client.post('/api/stripe/setup-session', json={})
    assert r.status_code == 403
    assert 'No primary account holder' in r.get_json()['error']
    assert not calls


def test_setup_session_allowed_for_support_account(client, appmod, monkeypatch):
    # Support has to be able to set a card up over the phone, and is never the recorded primary.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, primary=None, caller='admin@analytically.info')
    r = client.post('/api/stripe/setup-session', json={})
    assert r.status_code == 200
    assert r.get_json()['url'].startswith('https://checkout.stripe.com/')


def test_setup_session_is_setup_mode_not_a_subscription(client, appmod, monkeypatch):
    # SQL stays the system of record for what is owed. If this ever became mode='subscription'
    # Stripe would start computing amounts too, and the two engines would drift.
    wh, ap, calls = _stripe_env(appmod, monkeypatch)
    r = client.post('/api/stripe/setup-session', json={})
    assert r.status_code == 200
    mode = [kw for name, kw in calls if name == 'session.create'][0]
    assert mode['mode'] == 'setup'
    assert mode['currency'] == 'gbp'
    assert mode['metadata']['tenant_id'] == '11'


def test_stripe_customer_is_created_once_and_reused(client, appmod, monkeypatch):
    # A second Customer for the same practice would split its payment history and could leave a
    # card saved against the one we no longer read.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, customer_id='cus_EXISTING')
    r = client.post('/api/stripe/setup-session', json={})
    assert r.status_code == 200
    assert not [c for c in calls if c[0] == 'customer.create']
    assert [kw for name, kw in calls if name == 'session.create'][0]['customer'] == 'cus_EXISTING'


def test_payment_method_reports_no_card_before_setup(client, appmod, monkeypatch):
    # Drives the subscribe page: no Stripe customer yet means no card, without calling Stripe.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, customer_id=None)
    r = client.get('/api/stripe/payment-method')
    assert r.status_code == 200
    assert r.get_json() == {'has_card': False, 'can_manage': True}
    assert not calls


def test_payment_method_returns_brand_and_last4_only(client, appmod, monkeypatch):
    # Never a full card number -- only what the UI needs to say "Visa ending 4242".
    wh, ap, calls = _stripe_env(appmod, monkeypatch, customer_id='cus_EXISTING')
    r = client.get('/api/stripe/payment-method')
    assert r.status_code == 200
    body = r.get_json()
    assert body['has_card'] is True and body['brand'] == 'visa' and body['last4'] == '4242'
    assert set(body) == {'has_card', 'can_manage', 'brand', 'last4', 'exp_month', 'exp_year'}

def test_payment_method_tells_the_ui_who_may_change_the_card(client, appmod, monkeypatch):
    # can_manage is decided server-side. A non-primary admin can SEE that billing is set up but
    # must not be offered the control -- and, critically, the UI never works this out from a
    # roster, because support logins have no Dentally user and would be wrongly excluded.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, primary='someoneelse@practice.co.uk',
                                customer_id='cus_EXISTING')
    assert client.get('/api/stripe/payment-method').get_json()['can_manage'] is False

    wh, ap, calls = _stripe_env(appmod, monkeypatch, primary=None,
                                caller='admin@analytically.info', customer_id='cus_EXISTING')
    assert client.get('/api/stripe/payment-method').get_json()['can_manage'] is True


def test_attached_but_undefaulted_card_is_adopted(client, appmod, monkeypatch):
    # The real bug. Setup-mode Checkout ATTACHES the card but does not make it the default, so
    # the customer had a perfectly good visa 4242 while the app reported "No card on file" --
    # and the monthly invoice would have found nothing to charge. Reading must self-heal, because
    # the browser may never have made it back from Checkout to say so.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, customer_id='cus_EXISTING',
                                default_pm=None, cards=[_card('pm_NEW', last4='4242')])
    r = client.get('/api/stripe/payment-method')
    assert r.status_code == 200
    body = r.get_json()
    assert body['has_card'] is True and body['last4'] == '4242'
    # and it must PERSIST the choice, not just render it -- otherwise billing still can't charge
    modified = [kw for name, kw in calls if name == 'customer.modify']
    assert modified and modified[0][1]['invoice_settings']['default_payment_method'] == 'pm_NEW'


def test_no_cards_at_all_still_reports_no_card(client, appmod, monkeypatch):
    # Self-healing must not invent a card when none is attached.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, customer_id='cus_EXISTING',
                                default_pm=None, cards=[])
    assert client.get('/api/stripe/payment-method').get_json()['has_card'] is False
    assert not [c for c in calls if c[0] == 'customer.modify']


def test_setup_complete_makes_the_newest_card_the_one_we_bill(client, appmod, monkeypatch):
    # "Change card" must actually change it. Checkout attaches the new card alongside the old one
    # and leaves the default pointing at the old -- so without this the practice changes their
    # card, sees the new one, and we keep charging the cancelled one until it declines.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, customer_id='cus_EXISTING',
                                default_pm='pm_OLD',
                                cards=[_card('pm_NEW', last4='1111'), _card('pm_OLD', last4='4242')])
    r = client.post('/api/stripe/setup-complete', json={})
    assert r.status_code == 200
    assert r.get_json()['last4'] == '1111'
    modified = [kw for name, kw in calls if name == 'customer.modify']
    assert modified[0][1]['invoice_settings']['default_payment_method'] == 'pm_NEW'
    # one card on file: the superseded one is detached, so there is no ambiguity about what pays
    assert [pm for name, pm in calls if name == 'pm.detach'] == ['pm_OLD']


def test_setup_complete_is_idempotent(client, appmod, monkeypatch):
    # The browser can return twice (refresh, back button). Doing it again must not detach the
    # only card on file.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, customer_id='cus_EXISTING',
                                default_pm='pm_ONLY', cards=[_card('pm_ONLY')])
    r = client.post('/api/stripe/setup-complete', json={})
    assert r.status_code == 200
    assert not [c for c in calls if c[0] == 'pm.detach']


def test_setup_complete_refuses_non_primary(client, appmod, monkeypatch):
    # Same gate as the rest of billing -- it decides what card the practice gets charged on.
    wh, ap, calls = _stripe_env(appmod, monkeypatch, primary='someoneelse@practice.co.uk',
                                customer_id='cus_EXISTING')
    r = client.post('/api/stripe/setup-complete', json={})
    assert r.status_code == 403
    assert not [c for c in calls if c[0] in ('customer.modify', 'pm.detach')]


def test_setup_session_returns_to_the_invoices_tab(client, appmod, monkeypatch):
    # Returning to the app home page leaves the user to find their own way back to see whether it
    # worked -- and they cannot tell a saved card from a silent failure.
    wh, ap, calls = _stripe_env(appmod, monkeypatch)
    r = client.post('/api/stripe/setup-session', json={})
    assert r.status_code == 200
    kw = [k for name, k in calls if name == 'session.create'][0]
    assert 'settings=invoices' in kw['success_url'] and 'billing=saved' in kw['success_url']
    assert 'settings=invoices' in kw['cancel_url'] and 'billing=cancelled' in kw['cancel_url']


def test_invoice_email_prefers_invoice_over_primary(appmod, monkeypatch):
    # The whole point of a separate lookup. _tenant_primary_email uses the OPPOSITE precedence
    # because it answers "who is the main account holder" for monitor and token alerts. Reusing it
    # for billing sends invoices to the primary even when an accounts mailbox was entered.
    ap = _RecCursor({'Invoice_Email, Primary_Email': [('accounts@practice.co.uk', 'owner@practice.co.uk')]})
    monkeypatch.setattr(appmod, '_appdb_conn', lambda *a, **k: _RecConn(ap))
    assert appmod._tenant_invoice_email(11) == 'accounts@practice.co.uk'


def test_invoice_email_falls_back_to_primary(appmod, monkeypatch):
    # No accounts mailbox entered -- the primary is the right destination.
    ap = _RecCursor({'Invoice_Email, Primary_Email': [(None, 'owner@practice.co.uk')]})
    monkeypatch.setattr(appmod, '_appdb_conn', lambda *a, **k: _RecConn(ap))
    assert appmod._tenant_invoice_email(11) == 'owner@practice.co.uk'


def test_contact_sync_pushes_the_new_address_to_stripe(appmod, monkeypatch):
    # Stripe emails receipts and hosted invoices to the Customer's own email, set once at
    # creation. Without this the app's records change and Stripe keeps billing the old address --
    # silent until someone says they never got an invoice.
    wh = _RecCursor({'Stripe_Customer_ID FROM Billing.Account_Billing': [('cus_EXISTING',)],
                     'Tenant_Name': [('Maple Dental',)]})
    calls = []
    monkeypatch.setattr(appmod, '_stripe', lambda: _fake_stripe(calls))
    monkeypatch.setattr(appmod, '_tenant_invoice_email', lambda tid: 'accounts@practice.co.uk')
    assert appmod._stripe_sync_customer_contact(wh, 11) is True
    mod = [kw for name, kw in calls if name == 'customer.modify']
    assert mod and mod[0][0] == 'cus_EXISTING'
    assert mod[0][1]['email'] == 'accounts@practice.co.uk'
    assert mod[0][1]['name'] == 'Maple Dental'


def test_contact_sync_is_a_noop_without_a_stripe_customer(appmod, monkeypatch):
    # A practice that has never saved a card has no Customer to update.
    wh = _RecCursor({'Stripe_Customer_ID FROM Billing.Account_Billing': [(None,)]})
    calls = []
    monkeypatch.setattr(appmod, '_stripe', lambda: _fake_stripe(calls))
    assert appmod._stripe_sync_customer_contact(wh, 11) is False
    assert not calls


def test_contact_sync_failure_never_loses_the_save(appmod, monkeypatch):
    # This runs inside save_team, after the billing contact has been written. If Stripe is down,
    # the user's save must still stand -- so it returns False rather than raising.
    wh = _RecCursor({'Stripe_Customer_ID FROM Billing.Account_Billing': [('cus_EXISTING',)],
                     'Tenant_Name': [('Maple Dental',)]})

    def _boom():
        raise RuntimeError('stripe unreachable')
    monkeypatch.setattr(appmod, '_stripe', _boom)
    monkeypatch.setattr(appmod, '_tenant_invoice_email', lambda tid: 'accounts@practice.co.uk')
    assert appmod._stripe_sync_customer_contact(wh, 11) is False


# ── Removing the card on file ─────────────────────────────────────────────────
# Policy: replace-only while being billed. The refusal is the feature -- a practice that
# deleted its last card mid-subscription would look fine and silently stop paying.

def _remove_env(appmod, monkeypatch, paid_from, cancelled_at, cards=None,
                customer_id='cus_EXISTING', primary='owner@practice.co.uk',
                caller='owner@practice.co.uk'):
    cards = [_card('pm_ONE')] if cards is None else cards
    wh = _RecCursor({'Stripe_Customer_ID, Paid_From, Cancelled_At':
                         [(customer_id, paid_from, cancelled_at)]})
    ap = _RecCursor({'Primary_Email': [(primary,)] if primary else []})
    calls = []
    monkeypatch.setattr(appmod, '_auth', lambda: (caller, None))
    monkeypatch.setattr(appmod, '_get_user_info', lambda c, u: ('Owner', 7, [11], True))
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _RecConn(wh))
    monkeypatch.setattr(appmod, '_appdb_conn', lambda *a, **k: _RecConn(ap))
    monkeypatch.setattr(appmod, '_stripe', lambda: _fake_stripe(calls, 'pm_ONE', cards))
    return wh, ap, calls


def test_remove_card_refused_while_being_billed(client, appmod, monkeypatch):
    # The core guard. Paid_From in the past and no cancellation = actively charged.
    from datetime import date
    wh, ap, calls = _remove_env(appmod, monkeypatch, paid_from=date(2026, 1, 1), cancelled_at=None)
    r = client.post('/api/stripe/remove-card', json={})
    assert r.status_code == 409
    assert 'subscription is active' in r.get_json()['error']
    assert not [c for c in calls if c[0] == 'pm.detach']      # card untouched


def test_remove_card_refused_when_paid_from_is_null(client, appmod, monkeypatch):
    # NULL Paid_From means "bill from first access" (no trial) -- i.e. billing. Treating NULL as
    # "not charging" would let a paying practice delete its only card.
    wh, ap, calls = _remove_env(appmod, monkeypatch, paid_from=None, cancelled_at=None)
    assert client.post('/api/stripe/remove-card', json={}).status_code == 409
    assert not [c for c in calls if c[0] == 'pm.detach']


def test_remove_card_allowed_during_a_trial(client, appmod, monkeypatch):
    # Paid_From in the future = trial or free-forever. Nothing to bill, so nothing to protect.
    from datetime import date
    wh, ap, calls = _remove_env(appmod, monkeypatch, paid_from=date(2100, 1, 1), cancelled_at=None)
    r = client.post('/api/stripe/remove-card', json={})
    assert r.status_code == 200 and r.get_json()['has_card'] is False
    assert [pm for name, pm in calls if name == 'pm.detach'] == ['pm_ONE']


def test_remove_card_allowed_once_cancellation_has_taken_effect(client, appmod, monkeypatch):
    # Cancelled_At is the START OF NEXT MONTH, so a cancellation dated in the past means the
    # subscription has actually ended and the final invoice is behind us.
    from datetime import date, datetime as dt
    wh, ap, calls = _remove_env(appmod, monkeypatch, paid_from=date(2026, 1, 1),
                                cancelled_at=dt(2026, 2, 1))
    r = client.post('/api/stripe/remove-card', json={})
    assert r.status_code == 200
    assert [pm for name, pm in calls if name == 'pm.detach'] == ['pm_ONE']
    # and the default must be cleared, not left pointing at a detached card
    mod = [kw for name, kw in calls if name == 'customer.modify']
    assert mod and mod[0][1]['invoice_settings']['default_payment_method'] == ''


def test_remove_card_detaches_every_card_not_just_the_default(client, appmod, monkeypatch):
    # Belt and braces: if a stray second card ever got attached, "remove" must mean remove.
    from datetime import date
    wh, ap, calls = _remove_env(appmod, monkeypatch, paid_from=date(2100, 1, 1), cancelled_at=None,
                                cards=[_card('pm_ONE'), _card('pm_TWO')])
    r = client.post('/api/stripe/remove-card', json={})
    assert r.status_code == 200 and r.get_json()['removed'] == 2
    assert sorted(pm for name, pm in calls if name == 'pm.detach') == ['pm_ONE', 'pm_TWO']


def test_remove_card_refuses_non_primary(client, appmod, monkeypatch):
    from datetime import date
    wh, ap, calls = _remove_env(appmod, monkeypatch, paid_from=date(2100, 1, 1), cancelled_at=None,
                                primary='someoneelse@practice.co.uk')
    assert client.post('/api/stripe/remove-card', json={}).status_code == 403
    assert not calls
