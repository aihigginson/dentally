---
name: embed-token-scope-stops-at-one-tenant
description: "embed_token only passes customData when len(tids)==1, so a client holding two tenants falls back to the signed-in user's own RLS set — the group feature triggers this."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-12T17:28:46.017Z
---

`Web/app.py` `embed_token()` sets the RLS scope only for an unambiguous single practice:

```python
if len(tids) == 1:
    identity['customData'] = str(tids[0])
```

With two or more tenants in scope no `customData` is sent, and the model's rule falls back to
`USERPRINCIPALNAME()` — which resolves to **the signed-in user's own** permitted tenants, not the
acting client's. A vendor/staff login therefore sees EVERY tenant, regardless of which client the
app has narrowed to. `_get_user_info` narrows `tids` correctly; that narrowing simply never reaches
the model.

Found 2026-10-12 after removing `DEMO_TENANT_ID` (the demo host now resolves tids=[11,12]): the
demo showed £1,053K — all three dev tenants — while its picker said two practices. No exposure:
demo runs on the DEV backend, dev's t100 is "Test Practice", and PROD has a single active tenant so
`len(tids)==1` always holds there and every token names the practice.

**Why:** it is latent on prod and the GROUP feature is exactly what triggers it. The day a prod
client holds two tenants, a staff login acting as that client sees its own full set.

**How to apply:** the fix is two halves that MUST ship together — shipping either alone breaks the
working single-tenant path.
  1. app: always set it, as a delimited set — `identity['customData'] = "|".join(str(t) for t in tids)`.
     Always setting it removes the no-customData fallback by construction, rather than guarding a
     length.
  2. model: the RLS rule's equality test on `CUSTOMDATA()` becomes a membership test —
     `PATHCONTAINS(CUSTOMDATA(), [Tenant ID])`, which is still correct for one tenant.
The rule lives only in the model; `PBI_Dentally.csx` deliberately copies it from an existing table
rather than hard-coding it, so reading it needs XMLA and `FABRIC_SP_*`. See
[[a-new-model-table-has-no-rls]] and [[the-acting-practice-is-part-of-the-identity]].
