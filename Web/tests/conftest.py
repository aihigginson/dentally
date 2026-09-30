"""Pytest fixtures for Web/app.py.

app.py reads required config from env at import time, so we set dummy values
here (conftest is imported before the test modules) and add Web/ to sys.path so
`import app` works. No real Azure/Fabric/PBI calls are made — everything that
would hit the network is monkeypatched in the tests.
"""
import os
import sys

os.environ.setdefault('TENANT_ID', 'test-tenant')
os.environ.setdefault('CLIENT_ID', 'test-client')
os.environ.setdefault('CLIENT_SECRET', 'test-secret')
os.environ.setdefault('WORKSPACE_ID', 'test-workspace')
os.environ.setdefault('DATASET_ID', 'test-dataset')
os.environ.setdefault('FABRIC_SERVER', 'test-server')
os.environ.setdefault('REPORT_ID_REVENUE', 'revenue-report-id')
os.environ.setdefault('APP_ENV', 'test')

# Web/ (parent of this tests/ dir) onto the path so `import app` resolves.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest
import app as app_module


@pytest.fixture
def appmod():
    """The imported app module (for calling helpers / monkeypatching globals)."""
    return app_module


@pytest.fixture
def client():
    app_module.app.config['TESTING'] = True
    return app_module.app.test_client()


class FakeCursor:
    """Minimal pyodbc-cursor stand-in: returns canned rows for fetchone/fetchall."""
    def __init__(self, one_row=None, all_rows=None):
        self._one = one_row
        self._all = all_rows or []

    def execute(self, *args, **kwargs):
        return self

    def fetchone(self):
        return self._one

    def fetchall(self):
        return self._all


class FakeConn:
    def __init__(self, cursor=None):
        self._cursor = cursor or FakeCursor()

    def cursor(self):
        return self._cursor

    def close(self):
        pass


# ---------------------------------------------------------------------------
#  app.py caches the per-user authorization lookup and the report metadata at
#  MODULE scope, deliberately: a session mints ten embed tokens and would
#  otherwise open ten warehouse connections to ask the same two questions.
#
#  Module state outlives a test. The suite proved it the moment the cache went
#  in -- test_embed_success_for_provisioned_user passed alone and failed in the
#  suite, because an earlier test had already populated the entry for that UPN.
#  Clearing between tests keeps each one honest about what it actually sets up.
# ---------------------------------------------------------------------------
import pytest  # noqa: E402


@pytest.fixture(autouse=True)
def _clear_app_caches():
    import app
    app._authz_cache.clear()
    app._report_meta_cache.clear()
    yield
    app._authz_cache.clear()
    app._report_meta_cache.clear()
