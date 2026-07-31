# Plan Capitation — build plan

Monthly membership (Denplan) capitation revenue: a per-plan monthly fee, generated per member per
month, folded into Total Revenue, with a Plan Revenue Target. Data-entry screen for the rates.

## Resolved decisions (2026-07-31)

1. **Plan attribution is CURRENT plan only.** Verified: neither `Fact_Appointments.fk_Payment_Plan`
   nor `Fact_Invoice_Items.fk_Payment_Plan` hold the plan at time-of-service — both are the patient's
   *current* plan back-stamped onto all history (0 patients have >1 distinct plan across appointments
   or invoices). Dentally does not record historical scheme membership anywhere. So a patient's plan =
   `Dim_Patients.Payment_Plan_ID` (current).

2. **Value = per-plan monthly rate, effective-dated.** Input table `(Payment_Plan_ID,
   Effective_From_Date, Monthly_Value)`. Owner enters rates via a data-entry screen; sets an EARLY
   first effective date so history is covered. Rate as-of the month drives each fact row.
   **No rate covering a month ⇒ no record for that month** (owner's rule).

3. **Payments are a continuous monthly DIRECT DEBIT over a TENURE — not per visit/course.** The
   plan-style courses only define the ENDPOINTS; every calendar month in between gets a payment record
   regardless of whether the patient attended that month (verified via Adele on dev — clinical care
   lives in `Fact_Treatment_Plan_Items`, NOT invoices; she has 42 appts / 22 treatment plans but only
   2 invoice items = £7, both RETAIL brushes).
   - **Tenure start** = month of the patient's EARLIEST plan-style course.
   - **Tenure end**   = month of their LATEST plan-style course, UNLESS still on plan (current plan is
     a Denplan AND `Active=1`) — then ROLL FORWARD to the current month (today). Inactive Denplan
     members do NOT roll forward (tenure ends at last course).
   - Emit one payment record for EVERY calendar month from start to end inclusive
     (e.g. Jan-23..Feb-26 = 38 records).
   - SINGLE tenure per patient (simple MIN..MAX). Real patients may come/go on and off plan, but this
     is an approximation — do NOT model multiple tenures or gaps (owner decision 2026-07-31).
   A "plan-style course" = a completed course containing an Exam/Hygiene item that is plan-covered
   (`NHS_UDA_Value = 0` AND `Private_Treatment_Value = 0`; item `Charged=False`, `Price=0`).
   Verified the flag separates plan vs PAYG at scale (completed Exam/Hygiene items): Denplan variants
   are overwhelmingly `Charged=False` (Denplan C 10,985 F / 349 T), Private is the inverse (2,307 F /
   18,384 T). The 2,307 Private `Charged=False` rows ARE the former-members signal. Exam/Hygiene
   nomenclatures seen: 'Exam', 'Hygiene 20', 'Routine Hygiene' (also HEX etc — enumerate at build).

   **THREE-WAY funding distinction (verified via the Higginson family — Adele=Denplan, Alexandra=NHS,
   Andrew=Private):** the distinguisher is at the COURSE level (`Fact_Treatment_Plans`), NOT the item.
   - NHS-funded  → course `NHS_UDA_Value > 0`  (Alexandra: 10 courses, 10 UDA). EXCLUDE.
   - Private PAYG → course `Private_Treatment_Value > 0` / item `Charged=True` (Andrew: £2,073). EXCLUDE.
   - Plan-covered → NEITHER: `NHS_UDA_Value = 0` AND `Private_Treatment_Value = 0` (Adele: both 0). INCLUDE.
   GOTCHA: `Fact_Treatment_Plan_Items.NHS_Treatment_Cat` (e.g. 9317=exam, 9301=scale&polish) and
   `UDA_Band` are the clinical CATEGORY of the item, present on EVERY exam regardless of funding
   (Adele's Denplan exam also has NHS_Treatment_Cat=9317) — they do NOT indicate NHS funding. Use the
   course-level `NHS_UDA_Value` to detect NHS, never NHS_Treatment_Cat.
   So membership evidence = a completed course that contains an Exam/Hygiene item AND has
   `NHS_UDA_Value = 0` AND `Private_Treatment_Value = 0` (uncharged, non-NHS routine care).

4. **Attribution keys off the CURRENT plan being a Denplan, NOT active status.** If the patient's
   current plan is a Denplan (active OR inactive) we KNOW the rate → use it, Is_Estimated_Plan=0.
   Only when the current plan is genuinely non-Denplan (Private/NHS/etc) but they match the pattern
   are they a **former member** with an unrecoverable old plan → value at the **DEFAULT plan rate**
   (a designated fallback plan in the Input table), Is_Estimated_Plan=1. No default rate row ⇒ no
   records (per rule 2). Sense-check (dev, 2026-07-31): 1,379 active-Denplan + 66 inactive-Denplan get
   a KNOWN rate; only ~245 non-Denplan matchers (Private 230, NHS 13, IRH 2) use the default (~14%).
   **≥2-MONTH FLOOR for formers**: a default-rate former only qualifies if their plan-style tenure
   spans ≥2 months (MIN course month <> MAX course month, i.e. ≥2 plan-style courses in different
   months). This eradicates one-off stray uncharged exams: of the 245 non-Denplan matchers, 60 are
   single-day/same-month one-offs (dropped), leaving 185 genuine lapsing members (76 span 1-3yr, 71
   over 3yr). The floor applies ONLY to the default-rate (former) path; known-Denplan patients keep
   even a single-course tenure (they are real members).

5. **Full rebuild each run (DROP/CREATE), NOT incremental.** Late-arriving historical charges reopen
   closed periods; only a full rebuild catches them. ~1,414 current members × ~60 months ≈ 85k rows —
   trivial to rebuild. Matches the Gold fact DROP/CREATE pattern.

## Capitation plans (current member counts)
Denplan C 486 · Essentials A 373 · Denplan B 225 · D 129 · Essentials B 100 · Denplan A 72 · E 18 ·
Children 11  (≈1,414). `Private` / `NHS` / `Referral` / `IRH Fees` are NOT capitation.

## Components to build

### A. Input rate table (AppDB, write-back like Targets)
`Input.Plan_Capitation_Rate (Tenant_ID, Payment_Plan_ID, Effective_From_Date, Monthly_Value,
Is_Default BIT, DW_Updated_At)`. One open row per Denplan variant; `Is_Default=1` on the fallback
plan used for unrateable former-member months.

### B. Data-entry screen (Flask, Settings sub-nav)
- Lists the Denplan variants (from Dim_Payment_Plans, capitation only) with an editable Monthly_Value
  + Effective_From_Date; a "default plan" radio. Write-back to AppDB (POST), read on load (GET).
- Mirror the existing Targets write-back screen pattern.

### C. Gold.Fact_Plan_Capitation (DROP/CREATE full rebuild)
`(pk, Tenant_ID, fk_Patient, fk_Payment_Plan, fk_Date (month), Monthly_Value, Is_Estimated_Plan BIT)`.
Load SP:
1. Per patient, derive the TENURE from plan-style courses: start = MIN(course month), end =
   MAX(course month); if still on plan (current plan is a Denplan AND Active=1) roll end forward to
   the current month.
2. For current Denplan members: attributed plan = current plan; Is_Estimated_Plan=0.
   For evidenced non-Denplan patients: attributed plan = default plan; Is_Estimated_Plan=1.
3. Cross-join [tenure start..end] × Dim_Date month spine (one row PER calendar month in the tenure,
   attended or not); look up rate as-of month; emit row if a rate exists (else skip). Rate pulled
   from the Input table (mirrored into a Gold/Config table on load, like Targets/Effective_Targets).
Classify as GOLD_AGG (reads Dim_Patients + Fact_Appointments) so it orders after them.

### D. PBI + measures
- `Meta.usp_Create_Gold_Views` auto-view `_Plan Capitation`.
- Measure `Plan Capitation Revenue` = SUM(Monthly_Value) in filter context.
- Fold into `Total Revenue` (add Plan Capitation to the existing revenue measure).
- `Plan Revenue Target` measure (from a target Input, or derived) + variance card.

### E. Deploy
New table DDL + load SP + Meta regen + AppDB schema + Flask. Manifest V134+ (MIGRATE AppDB table,
DEPLOY Gold table/SP, EXEC load + Meta.usp_Create_Gold_Views). Deploy dev → verify → prod.

## Open detail to confirm at build time
- Exact "zero-cost exam/hygiene" test: appointment Reason IN (Exam/Hygiene/Scale&Polish/HEX...) AND
  not NHS AND no invoice charge on that date. Refine against real data during build.
- Plan Revenue Target source: flat annual figure per tenant, or sum of (members × rate)? TBD with owner.
