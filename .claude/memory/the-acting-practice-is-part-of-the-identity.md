---
name: the-acting-practice-is-part-of-the-identity
description: "A cache keyed on the UPN alone served one practice's tenant set for another, and embed-token turned that into two practices added up under one name."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-07T10:40:44.654Z
---

`_get_user_info` narrows `tids` by the acting client — that IS the mechanism by which a support
login views one practice. `_authz_for` cached the result on the **UPN alone**, so the same person
with a different practice picked got the previous practice's answer for up to `_AUTHZ_TTL` (60s).

It surfaced at exactly one caller: **`/api/embed-token`, where `tids` decides RLS.** With two
permitted tenants and no single one in scope, `customData` is not set and the model ADDS THE
PRACTICES UP. On dev, 2026-10-07, with Maple selected: £786K on screen = Maple £468,703 + demo
£314,073 + £3,123. Every other route resolves through `_get_user_info` directly, so the UI named
one practice while the reports showed two — which is what makes it hard to spot.

Fixed by keying on `(upn, _acting_client_id(upn), _acting_tenant_id(upn))`.

**How to apply:** anything cached per user must include the acting scope in its key, because the
acting practice is part of the identity, not a display preference. And prod was unaffected only by
luck — no prod user is granted more than one tenant, so `len(tids) == 1` always held. Do not read
"prod is fine" as "the code is right"; at customer #2 this would have been live.

**Also a lesson about me:** the owner reported tenant 11 practitioners on a report, I checked the
three names from an EARLIER prod screenshot, found them to be genuine Maple staff, and said there
was no leak. He pushed back with the right screenshot and there was. Check the artefact in front of
the user, not the one you happen to have. Related: [[a-new-model-table-has-no-rls]],
[[my-data-is-unfiltered-for-vendor-accounts-by-design]].
