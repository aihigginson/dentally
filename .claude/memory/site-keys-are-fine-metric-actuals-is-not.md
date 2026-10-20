---
name: site-keys-are-fine-metric-actuals-is-not
description: "Transactional facts all resolve their site; Fact_Metric_Actuals writes -1 for every practice-level metric, so scorecard tiles cannot follow a site selection."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-12T12:15:00.446Z
---

Measured 2026-10-12 on DEV. Every transactional Gold fact resolves `fk_Practice_Site` — zero
`-1` rows across `Fact_Appointments`, `Fact_Treatment_Plans`, `Fact_Revenue`, `Fact_Invoices`,
`Fact_Payments`, `Fact_Recalls`, `Fact_Plan_Spell`, `Fact_New_Patients`, `Fact_Lapsed_Patients`
and `Fact_Practitioner_Diaries` (which DOES have a site column).

`Gold.Fact_Metric_Actuals` is the exception: all 15 practice-level metrics write `-1`
(diary_fill, chair_utilisation, dna_rate, cancellation_frequency, revenue_per_clinical_hour,
revenue_per_dentist_hour, exam_ratio, book_before_you_leave, acceptance_rate, avg_plan_value,
new_patients, patient_tracked_in_surgery, short_notice_cancellation_rate, open_courses,
open_courses_without_appt). 21 more are mixed — practitioner rows carry a site, the
practice-level roll-up row does not.

**Why:** a comment in `Web/index.html` claimed the opposite — that Fact_Practitioner_Diaries had
no site column and appointments were all -1 — and that false claim justified hiding the site
filter and shaped how I described multi-site for months. The filter is still hidden for
single-site practices, but only because it would be a no-op.

A second, subtler gap found the same day: appointment -> site is the PRACTITIONER'S attached
site, not where the appointment happened. `Gold.usp_Load_Fact_Appointments.StoredProcedure.sql:263`
falls back to the practitioner's site when the appointment carries none (seeded tenants never carry
one -- Bronze.Appointments.Practitioner_Site_ID is 100% NULL on t11 and t12, fully populated on
t100). And even on real Dentally data `Practitioner_Site_ID` is the site the practitioner is
ATTACHED to; `Room_Site_ID` -- where it actually took place -- is NULL until rooms are configured
per site (`Silver.usp_Load_Appointments.StoredProcedure.sql:13-16`). So a dentist working Mondays at
one surgery and Tuesdays at another has every appointment booked to one site. Harmless where each
practitioner sits at one site; wrong for a real multi-site practice.

**How to apply:** site filtering is safe to demo on transactional pages. Do NOT claim site-level
KPIs until Fact_Metric_Actuals carries a site. t11 and t100 are single-site, so "zero bad" there
proves nothing about multi-site — test on tenant 12. See [[group-target-aggregation-is-unresolved]]
and [[read-the-schema-before-querying-it]].
