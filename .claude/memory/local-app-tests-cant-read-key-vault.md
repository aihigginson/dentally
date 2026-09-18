---
name: local-app-tests-cant-read-key-vault
description: "Importing Web/app.py locally breaks Key Vault, because load_dotenv puts AZURE_* back into the environment."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-18T10:13:26.867Z
---

`Web/app.py` calls `load_dotenv()` at import, so `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` /
`AZURE_TENANT_ID` from `Web/.env` land in `os.environ`. `DefaultAzureCredential` then authenticates
as that app registration (`ea34f12f…`), which has **no Key Vault access** — so every `_stripe()` /
`_kv_get()` call fails `(Forbidden)` and the Stripe half of any local test is dead.

Clearing them *before* the import does nothing; `load_dotenv()` puts them straight back. Pop them
**after** `import app`, and `DefaultAzureCredential` falls through to the `az` CLI identity
(`admin@analytically.info`), which can read the vault:

```python
import app
for k in ('AZURE_CLIENT_ID', 'AZURE_CLIENT_SECRET', 'AZURE_TENANT_ID'):
    os.environ.pop(k, None)
```

This never happens in the container: there is no `.env` there, so the credential chain reaches the
container app's **system-assigned managed identity**, which does have access. A `Forbidden` from
Key Vault on the laptop therefore says nothing about whether the deployed app works.

Worth the trouble because driving the real endpoints through `app.test_client()` — faking only
`_validate_id_token` — is the only thing that catches warehouse and Stripe faults that unit tests
structurally cannot. See [[fabric-writes-from-the-app-need-autocommit]].
