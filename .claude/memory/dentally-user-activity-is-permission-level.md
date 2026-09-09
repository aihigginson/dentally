---
name: dentally-user-activity-is-permission-level
description: Dentally's /users has no 'active' field - permission_level is the activity signal (0 = deactivated).
metadata:
  type: project
---

Dentally's `/users` payload has **no `active` field**. The activity signal is
**`permission_level`** — `0` means deactivated. (Verified against the live API on
2026-09-09; keys returned are allowed_sites, created_at, email, first_name, id,
image_url, import_id, last_login, last_name, middle_name, mobile_phone,
permission_level, practice_id, role, site_id, title, updated_at, uuid.)

**Do not infer user activity from the practitioner record.**
`Silver.Practitioners.Practitioner_Active` is a *different* thing: front-office
staff frequently have a practitioner record, and it is deactivated when they stop
being a bookable diary entry while their user account stays live. Using it as a
proxy hid two active administrators (permission_level 4) from the subscriptions
roster on tenant 100 — 28 of the 30 people it excluded were genuinely level 0, so
the bug was invisible in aggregate.

On tenant 100 the levels are clean: level 0 = 28 rows (all inactive), level 2 = 13,
level 4 = 4. `Gold.Dim_Users.Permission_Level` is authoritative from the first
build after release V154 (before that it reads NULL — Bronze never staged it).
