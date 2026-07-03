"""
xero_store.py  --  Token + org-map storage for the Xero extractor / lander / notebook.

A Xero *connection* is one OAuth consent (one refresh token) that can cover one or
more organisations (tenants). Each client authorises your app against their own Xero,
producing their own connection. This module abstracts where those connection blobs
live so the same code runs against the Demo Company today and real clients in
production with no code change -- only an env var.

The store holds a **dict of connections**, keyed by a connection key:
    { "<connKey>": {"tokens": {...}, "tenants": [{"tenantId","tenantName"}, ...]}, ... }
This is the exact shape the Fabric notebook (Ingest_Xero) reads from the single
`xero-tokens` Key Vault secret.

Backends (env var XERO_TOKEN_STORE):
  local   (default)  API/xero_token.local.json -- the dev/Demo store (a JSON file).
  keyvault           Azure Key Vault: the whole dict lives in ONE secret, `xero-tokens`.
                     Auth via DefaultAzureCredential (az-cli / VS sign-in locally; the
                     workspace/pipeline identity in Fabric). Vault URL from env
                     XERO_KEYVAULT_URL, defaulting to the Analytically vault. Needs
                     azure-keyvault-secrets installed.

Keep DEV on the local file and PRODUCTION on Key Vault as SEPARATE stores: a refresh
token rotates on every use, so the laptop extractor and the nightly notebook must not
share one connection or they invalidate each other's token.

Org -> Dentally Tenant_ID mapping lives in creds.XERO_ORG_MAP (gitignored), keyed by
Xero tenantId (GUID). Real client GUIDs must never be committed. See resolve_org().
"""
import importlib.util
import json
import os

HERE       = os.path.dirname(os.path.abspath(__file__))
TOKEN_FILE = os.path.join(HERE, "xero_token.local.json")
KV_SECRET  = "xero-tokens"
DEFAULT_VAULT_URL = "https://kv-analytically.vault.azure.net/"


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

    Unmapped orgs are skipped by the extractor (so a consent that also covers an org you
    don't analyse -- e.g. your own company -- is ignored). As a first-run convenience,
    an org whose name contains 'demo company' falls back to Tenant_ID 99.
    """
    org_map = getattr(creds, "XERO_ORG_MAP", {}) or {}
    entry = org_map.get(tenant.get("tenantId"))
    if entry:
        return {"tenant_id": entry["tenant_id"],
                "default_site_id": entry.get("default_site_id")}
    if "demo company" in (tenant.get("tenantName", "") or "").lower():
        return {"tenant_id": 99, "default_site_id": None}
    return None


# ── token store backends (dict of connections) ────────────────────────────────

def _backend():
    return os.environ.get("XERO_TOKEN_STORE", "local").lower()


def _vault_url():
    return os.environ.get("XERO_KEYVAULT_URL", DEFAULT_VAULT_URL)


def _kv_client():
    # Lazy import so local dev doesn't need azure-keyvault-secrets installed.
    from azure.identity import DefaultAzureCredential
    from azure.keyvault.secrets import SecretClient
    return SecretClient(vault_url=_vault_url(), credential=DefaultAzureCredential())


def load_all():
    """Return the whole {connKey: {tokens, tenants}} dict (empty if nothing stored)."""
    if _backend() == "keyvault":
        try:
            raw = _kv_client().get_secret(KV_SECRET).value
        except Exception:
            return {}
        return json.loads(raw) if raw else {}
    if not os.path.exists(TOKEN_FILE):
        return {}
    with open(TOKEN_FILE) as f:
        data = json.load(f)
    # Back-compat: the original file held a single un-keyed {tokens, tenants} blob.
    if isinstance(data, dict) and "tokens" in data and "tenants" in data:
        return {"local": data}
    return data


def save_all(conns):
    """Persist the whole connections dict."""
    if _backend() == "keyvault":
        _kv_client().set_secret(KV_SECRET, json.dumps(conns))
        return
    with open(TOKEN_FILE, "w") as f:
        json.dump(conns, f, indent=2)


def list_connections():
    """Connection keys to iterate (each is one OAuth consent / token blob)."""
    return list(load_all().keys())


def load_connection(key):
    """Load one connection blob {'tokens', 'tenants'} by key (or None)."""
    return load_all().get(key)


def save_connection(key, blob):
    """Add/replace one connection and persist (read-modify-write of the whole dict)."""
    conns = load_all()
    conns[key] = blob
    save_all(conns)
