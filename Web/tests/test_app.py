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
