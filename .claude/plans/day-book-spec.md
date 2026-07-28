# Day Book — agreed design (recovered from 2026-07-22 session notes)

> Source of truth. Recovered 2026-07-23 after a straw man was built the wrong way.
> Status: **business requirement, not yet a solved solution** (user's words: "still nebulous").

## ⭐ REDIRECT 2026-07-28 — short-term focus = FILLING THE FORWARDS DIARY
User steer: long term the Day Book is likely a **more integrated piece talking directly to the
Dentally API** (two-way / live). **Short term, concentrate on filling the forwards diary.** Build:

- **Opening screen = Forwards Availability** — reuse the *Forwards Availability* visual from the
  **My Data** report, but as a **manager cross-practitioner view with `Practitioner Full Name` on
  each row** (My Data is RLS-locked to self; the Day Book version lists all practitioners).
- **Links through to three worklists** (drill/nav from the opening screen):
  1. **Open Plans — No Appointments** (open treatment courses with no future appointment)
  2. **Recalls Not Sent**
  3. **Recalls Not Booked**

This supersedes the 5-lens build below for now — the old "Filling Diary" lens is the centrepiece,
reframed as: availability overview → the three "who to contact" lists that fill that availability.
The Today's-Patients / Tracking / BBYL lenses are deferred (revisit with the API-integrated version).

## The requirement (user, verbatim, 2026-07-22)
> "It wants to be a **single view of patients with different tasks**. Todays patients is to flag
> any issues, namely missing emails, phone numbers, high risk DNA, outstanding balances. **Regular
> patients with no issues are filtered out.** Filling diary is a list of possible people to contact
> to fill the diary, primarily open courses with no appointments but overlapping with recalls.
> Recalls is simply a tracking list of who should be in the recall process. Tracking in surgery and
> BBYL are retrospective metrics only but need to be shown over time to show whether the reception
> staff are following process. On the whole this whole report is still nebulous with a business
> requirement rather than a solution."

## Structural decision (user answered): **ONE unified task-flagged patient list + lenses**
Not separate tables. One patient-grain row per patient **that has ≥1 open task**; flag columns per
task; **a patient with several issues appears once**; **no-issue patients are hidden**. The action
tabs are just *filters* (lenses) over that same list. Agreed preview:

```
PATIENT ACTIONS         lens: [Today] [Fill Diary] [Recalls]
Patient       Email Phone DNA   Bal    OpenCourse Recall
Jane Smith      x                £120
Amir Patel            x    high              Open    Due
(row appears if ANY flag set; no-issue patients hidden)
```

## The five tabs
**Lenses over the unified flagged list (worklists):**
1. **Today's Patients** — patients with an appointment **today**, filtered to those with an issue:
   missing email, missing phone, high-risk DNA, outstanding balance. Front-desk pre-check.
2. **Filling Diary** — contact list to fill the diary: **primarily open courses with no appointment**,
   overlapping with recalls.
3. **Keeping Patients (Recalls)** — tracking list of who should be in the recall process (due/overdue).

**Retrospective process-compliance trends (metrics over time, NOT worklists):**
4. **Tracking (in surgery)** — is reception following the in-surgery tracking process? Trend over time.
5. **BBYL (Book Before You Leave)** — rebook-at-checkout rate over time. Trend.

## Data
- Ideal: **Gold.Fact_Patient_Actions** (patient-grain, one row/patient, BIT/value flag columns:
  Is_Email_Missing, Is_Phone_Missing, Is_DNA_Risk (>=2 DNAs/12mo), Has_Outstanding_Balance (>GBP0),
  Has_Open_Course_No_Appt, Has_Recall_Due; + Has_Appt_Today for the Today lens).
- Straw-man-from-existing mapping: email/phone blank on `List Patients`; `_Invoices[Invoice Amount
  Outstanding]`; `Open Courses Without Appointment`; `_Recalls[Due Date/Overdue Band]`. **DNA risk**
  and **Has_Appt_Today** are the two that need real work (`_Appointments` only exposes `Rebooked
  Status` today — Today lens needs appointment-grain columns surfaced). BBYL / in-surgery tracking:
  `Book Before You Leave` measure exists; `Tracked_Appointments`/`BBYL_Appointments` exist on the
  Gold aggregate.

## Report styling conventions (MANDATORY — read off My_Data / Revenue)
These apply to ALL reports and the Day Book must follow them:
1. **No internal header bar.** No title textbox. The KPI ribbon sits at **y=0** (the app supplies branding/nav).
2. **Consistent KPI ribbon on top** — a single full-width `cardVisual` at y=0 (the "golden card" multicard, per-field conditional formatting via the naming contract `X` / `X Target` / `X vs Target`).
3. **Single page + overlaid bookmarks** — ONE report page; a `bookmarkNavigator` (~y=42, h≈23) switches views; content visuals are stacked at the same position and shown/hidden by **bookmarks** (`suppressData:true`, `display.mode=hidden`). NOT separate pages, NOT `pageNavigator`.
4. Slicer(s) right-aligned on the navigator row; detail drill `actionButton`s top-right.
Layout skeleton: `y0 cardVisual (KPI ribbon)` → `y42 bookmarkNavigator + slicer` → `y~70 overlaid content (worklist table / trend charts, toggled per lens)`.

## What the first straw man got WRONG (don't repeat)
- Built 5 disconnected pages of generic KPI cards + two unrelated tables.
- Added a header bar (should be none) and used pageNavigator + separate pages (should be single page + overlaid bookmarks).
- Missed that it's ONE flagged patient list filtered 3 ways; missed "no-issue patients hidden".
- Treated Tracking/BBYL as KPI cards, not retrospective trends.
