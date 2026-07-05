# Dentally real-API reconciliation

Blueprint for the real ingestion (task B). Compares REAL `api.dentally.co/v1` responses
(from `python API/dentally_extract.py`, first customer "Maple Dental" = Tenant_ID 100,
2026-07-05) against the mock-driven warehouse the pipeline currently assumes. The current
Bronze/Silver was modelled on Dentally and mostly matches — but real Dentally **nests**
data, uses **GUID ids**, and has a few **type/semantic** differences that the ingestion
must handle. This drives the real `Stage_Ingest` build + any Bronze/Silver schema fixes.

## Confirmed
- Auth (KV token, Bearer) works. Every entity reachable; deep pagination works.
- Whole cake: ~1.9M records + **113,341 appointments** (via `after`/`before`).
- Base `https://api.dentally.co/v1`. `practice` is a **single object** (not a list).

## Cross-cutting rules (apply to the flatten/map layer)
1. **Flatten nesting** the mock kept flat/separate:
   - `practitioner.user{}` → name/email/**role** (`first_name`,`last_name`,`role`); `practitioner.site{}` → full site. (Practitioner NAME + ROLE come from the nested user.)
   - `payment.explanations[]` → the payment→invoice allocations (mock had separate `/payment_explanations` + `/payment_allocations` endpoints; real nests them).
   - Arrays: `treatment_plan_item.teeth[]`/`surfaces`, `custom_fields[]`, practitioner `specialisms[]`/`contract_targets[]`, user `allowed_sites[]`.
2. **Drop special-category / PII** on patients (DPIA V011/V012 — these MUST NOT land): `date_of_birth`, `gender` (bool), `ethnicity`, `nhs_number`, `ni_number`, `pps_number`, `medical_alert`(bool)/`medical_alert_text`, `special_needs`, `occupation`, `school_name`, `emergency_contact_*`, `proof_of_identification`, `suspicious_identity`, `image_url`. KEEP: name, contact (phone/email + `use_email`/`use_sms`/`preferred_phone_number`), `marketing`, recall dates/intervals, `dentist_id`/`hygienist_id`, `acquisition_source_id`, `payment_plan_id`, `site_id`, `active`, `account_id`, town/postcode/county.
3. **Drop free-text clinical** (V012): `treatment_plan_item.notes`, `appointment.notes`, patient-facing free-text descriptions. (Treatment-DEFINITION `nomenclature` on `/treatments` is reference data — keep as the treatment name.)
4. **Type/semantic fixes:**
   - `invoice_items.nhs_charge` is a **BOOLEAN** (is-NHS flag), but `Gold.Fact_Invoice_Items.NHS_Charge` is `decimal(12,2)` → **schema/mapping fix** (make it a flag, or drop).
   - **GUID ids** (string) for `sites`, `invoice_items`, `contracts`, `practice`, `appointment.practitioner_site_id`, patient `uuid` — target columns must be `varchar` (mostly already are; audit any int assumptions).
   - Amounts are **strings** (`"-76.0"`) → Bronze `TRY_CAST` already handles.
   - `payment_plans` field name has a **typo in the API**: `monthly_memberhsip_fee` — map the misspelled key.
5. **Nulls to handle:** `appointment.patient_id` null = **diary blocks** (e.g. `reason:"Bank Holiday"`, `state:"Pending"`); `invoice_item.practitioner_id`/`treatment_plan.*` null = opening-balance/import rows.

## Per-entity (surveyed 15) — notes vs the mock
| Entity | Endpoint notes | Key transforms |
|---|---|---|
| practice | **singular object** | flat; `custom_patient_field_label_1/2` present |
| sites | GUID id | flat |
| users | 94; separate endpoint | flat; also nested inside practitioner |
| practitioners | 45 | **flatten `.user` (name/role) + `.site`**; `uda_target`/`uoa_target`/`contract_targets[]` |
| treatments | 333 | flat; `nomenclature`/`patient_nomenclature`/`nhs_treatment_cat`/`uda_band`/`treatment_category_id` |
| treatment_categories | 22 | just `id`,`name` |
| payment_plans | 28 | durations + `monthly_memberhsip_fee` (typo) |
| contracts | GUID id | `target`(UDA target), `uda_value`(rate), `uoa_target/value`, `nhs_site_id` → Fact_Contracts |
| patients | 27,745 | **DROP PII (rule 2)**; keep contact/recall/assignments |
| appointments | 113,341; **needs `after`/`before`** | full lifecycle (`state`,`pending_at`,`cancelled_at`,`did_not_attend_at`,`arrived_at`,`completed_at`); patient_id null = block |
| invoices | 48,937 | no practitioner (derive from items); amounts strings |
| invoice_items | 90,139; GUID id | **`nhs_charge` boolean (fix)**; `practitioner_id`/`total_price` → production/contribution |
| treatment_plans | 372,430 | `nhs_uda_value`/`nhs_completed_uda_value`/`private_treatment_value` = **UDA + private production** (fixes NHS understatement for practitioner P&L) |
| treatment_plan_items | 1,321,047 | `price`,`practitioner_id`,`teeth[]`,`custom_fields[]`; drop `notes` |
| payments | 47,594 | **flatten `explanations[]`** → allocations; amounts strings |

## Remaining entities (probed 2026-07-05)
Resolved:
| Entity | Endpoint | total | notes |
|---|---|---|---|
| sundries | `sundries` | 37 | id/name/nickname/price/site_id |
| nhs_claims | `nhs_claims` | 12,922 | awarded/expected_uda, dentist/patient_charge, claim_status, contract_id, ortho → Fact_NHS_Claims |
| acquisition_sources | `acquisition_sources` | 148 | active/name/notes/show_in_portal |
| cancellation_reasons | **`appointment_cancellation_reasons`** | 15 | reason/reason_type/archived (NOT `cancellation_reasons`) |
| patient_referrals | `patient_referrals` | 611 | `referrable_type`/`referrable_attributes` (nested), status, reference |
| patient_stats | `patient_stats` | 27,745 | rollups: first/last/next appt+exam+S&P dates, `total_invoiced`, `total_paid`, `nhs_exemption_code` |
| treatment_appointments | `treatment_appointments` | 548,512 | links treatment_plan_id ↔ appointment_id (which treatments in which appt) |

Resolved (2nd probe):
- **fees** — `fees?treatment_id=<id>` → 5 price/duration tiers (`price_one..five`, multi-visit) per (treatment × payment_plan). **Pulled per-treatment** (iterate the ~333 treatments), not bulk.
- **recalls** — plain `recalls` → 22,484 (the earlier 500 was transient). Reminder/workflow fields → Fact_Recalls.
- **rooms** — `total=0` even with `site_id`: this practice has **no rooms/surgeries configured** in Dentally. Dim_Rooms just empty for them (not a bug).

**Practitioner diary — `rota_practitioner_diaries` (found in docs):** `GET /v1/rota_practitioner_diaries?after=&before=&practitioner_id=&site_id=` (requires the **Rota feature** enabled for the practice; generated up to 4yr forward). One row per practitioner-per-day: `day`, `start_time`, `end_time`, `unavailable` (bool), `practitioner_id`, and **`breaks[]` EMBEDDED** (id, name, start_time, end_time). = the mock's `practitioner_diary_entries` (the day rota) + `practitioner_diary_breaks` (**flatten the embedded `breaks[]`**, not a separate endpoint). Needs `after`/`before` like appointments. (Forward free-slot lookup, if ever needed, = `/appointments/availability`.) Confirm the practice has Rota enabled (else empty).

## SURVEY COMPLETE — every warehouse entity accounted for. Next: build the real Stage_Ingest.

## Ingestion build notes
- **Extractor pagination FIX (before any `--full`):** `patients`/`treatment_plan_items`/
  `payments` stopped after 1 page in the sample — don't rely on `meta.total_pages` alone;
  keep paging while a page returns `per_page` rows (or the total isn't yet reached).
- **Appointments** require `after`/`before` (plain params, NOT `filter[start_time]`); can
  also filter by `patient_id`/`practitioner_id` (plain).
- **Rate limit:** `RateLimit-Remaining` ~3600 budget, ~1/call; full initial pull ~20k calls
  → paginate + back off (429/low budget) + **incremental via `updated_after`** after load.
- Tenant_ID stamped on every row (100 here). Real tenants live in PROD; token per env in KV.
