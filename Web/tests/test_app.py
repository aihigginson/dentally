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


def test_get_user_info_provisioned(appmod):
    cur = FakeCursor(one_row=('Alice', 7, 1), all_rows=[(11,), (12,)])
    name, client_id, tids, maintain = appmod._get_user_info(cur, 'alice@x.com')
    assert name == 'Alice'
    assert client_id == 7
    assert tids == [11, 12]
    assert maintain is True


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
    def __init__(self, proc, ing):
        self._proc, self._ing, self._which = proc, ing, None
    def execute(self, sql, *a):
        self._which = 'proc' if 'Process_Execution_Log' in sql else 'ing'
        return self
    def fetchall(self):
        return self._proc if self._which == 'proc' else self._ing


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
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _MonConn(_MonCursor(proc, ing)))
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
    monkeypatch.setattr(appmod, '_fabric_conn', lambda *a, **k: _MonConn(_MonCursor([], ing)))
    monkeypatch.setattr(appmod, '_send_email', lambda to, subj, body, **kw: sent.append((to, subj, body, kw)))
    j = client.post('/api/monitor/health', headers={'X-Monitor-Key': 'secret'}).get_json()
    assert j['emails_enabled'] is True and j['principals_notified'] == 1 and j['bad_token_tenants'] == [100]
    tos = [s[0] for s in sent]
    assert appmod.MONITOR_NOTIFY in tos                       # operator summary
    assert tos.count('craig@mapledental.co.uk') == 1          # exactly ONE nudge to the main account
    nudge = next(s for s in sent if s[0] == 'craig@mapledental.co.uk')
    assert nudge[3].get('sender') == appmod.SUPPORT_FROM      # sent FROM Support@
    assert 'settings=dentally' in nudge[2] and 'Personal Access Token' in nudge[2]


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
