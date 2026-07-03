"""
xero_store.py  --  Token + org-map storage for the Xero extractor / lander.

A Xero *connection* is one OAuth consent (one refresh token) that can cover one or
more organisations (tenants). Each client authorises your app against their own
Xero, producing their own connection. This module abstracts where those connection
blobs live so the same extractor code runs against the Demo Company today and real
clients in production with no code change -- only an env var.

Backends (env var XERO_TOKEN_STORE):
  local    (default)  API/xero_token.local.json -- the single-file dev/Demo store.
  keyvault            Azure Key Vault, one secret per connection named
                      'xero-token-<key>'. Auth via DefaultAzureCredential (managed
                      identity in the container app; az-cli / VS sign-in locally).
                      Requires env XERO_KEYVAULT_URL. azure-keyvault-secrets is
                      imported lazily so local dev needn't install it.

A connection blob is the shape xero_auth.py writes: {"tokens": {...}, "tenants":
[{"tenantId","tenantName"}, ...]}. The extractor rotates the refresh token every
run (Xero rotates it on use) and calls save_connection() to persist it.

Org -> Dentally Tenant_ID mapping lives in creds.XERO_ORG_MAP (gitignored), keyed
by Xero tenantId (GUID). Real client GUIDs must never be committed, so the map is
part of the local creds, not source control. See resolve_org().
"""
import importlib.util
import json
import os

HERE       = os.path.dirname(os.path.abspath(__file__))
TOKEN_FILE = os.path.join(HERE, "xero_token.local.json")
LOCAL_KEY  = "local"
KV_PREFIX  = "xero-token-"


# ── creds + org map ───────────────────────────────────────────────────────────

def load_creds():
    """Load the gitignored xero_creds.local.py (dotted filename -> load by path)."""
    path = os.path.join(HERE, "xero_creds.local.py")
    if not os.path.exists(path):
        raise SystemExit("Missing API/xero_creds.local.py (copy xero_creds.example.py).")
    spec = importlib.util.spec_from_file_location("xero_creds_local", path)
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def resolve_org(creds, tenant):
    """Map a connected Xero org -> {tenant_id, default_site_id} or None if unmapped.

    Unmapped orgs are skipped by the extractor (so a consent that happens to cover an
    org you don't analyse -- e.g. your own company -- is ignored). As a convenience
    for first-run against Xero's Demo Company, an org whose name contains 'demo
    company' falls back to Tenant_ID 99 when no explicit map entry exists.
    """
    org_map = getattr(creds, "XERO_ORG_MAP", {}) or {}
    entry = org_map.get(tenant.get("tenantId"))
    if entry:
        return {"tenant_id": entry["tenant_id"],
                "default_site_id": entry.get("default_site_id")}
    if "demo company" in (tenant.get("tenantName", "") or "").lower():
        return {"tenant_id": 99, "default_site_id": None}
    return None


# ── token store backends ──────────────────────────────────────────────────────

def _backend():
    return os.environ.get("XERO_TOKEN_STORE", "local").lower()


def _kv_client():
    # Lazy import so local dev doesn't need azure-keyvault-secrets installed.
    from azure.identity import DefaultAzureCredential
    from azure.keyvault.secrets import SecretClient
    url = os.environ.get("XERO_KEYVAULT_URL")
    if not url:
        raise SystemExit("XERO_TOKEN_STORE=keyvault but XERO_KEYVAULT_URL is not set.")
    return SecretClient(vault_url=url, credential=DefaultAzureCredential())


def list_connections():
    """Return the connection keys to iterate (each is one OAuth consent / token blob)."""
    if _backend() == "keyvault":
        kv = _kv_client()
        return [p.name[len(KV_PREFIX):] for p in kv.list_properties_of_secrets()
                if p.name.startswith(KV_PREFIX)]
    return [LOCAL_KEY]


def load_connection(key):
    """Load a connection blob {'tokens', 'tenants'} by key."""
    if _backend() == "keyvault":
        return json.loads(_kv_client().get_secret(KV_PREFIX + key).value)
    with open(TOKEN_FILE) as f:
        return json.load(f)


def save_connection(key, blob):
    """Persist a connection blob (called after the refresh-token rotates)."""
    if _backend() == "keyvault":
        _kv_client().set_secret(KV_PREFIX + key, json.dumps(blob))
        return
    with open(TOKEN_FILE, "w") as f:
        json.dump(blob, f, indent=2)
