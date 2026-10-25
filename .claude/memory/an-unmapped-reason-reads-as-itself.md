---
name: an-unmapped-reason-reads-as-itself
description: "Appointment_Reason is COALESCE(map.Category, raw text), so an unmapped reason looks like a healthy category and the map can be nearly empty undetected."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-22T10:17:33.584Z
---

`Gold.usp_Load_Fact_Appointments` sets
`Appointment_Reason = COALESCE(arm.Category, NULLIF(TRIM(a.Reason), ''))`.

So an unmapped reason **does not read as unmapped -- it reads as itself**. Maple's own text
for a check-up is literally `Exam` and for treatment `Continuing Treatment`, character for
character the category names. Querying `Fact_Appointments WHERE Appointment_Reason = 'Exam'`
returned 31,741 rows and looked like a working mapped category. `Silver.Appointment_Reason_Map`
matched **none** of them.

I checked exactly that and concluded the map was fine. It was recognising **29.5%** of the
tenant's completed appointments. Anything doing a real JOIN to the map -- the V229 exam
ownership rule -- ran on a quarter of the exams (2,911 patients instead of 6,932). V230
mapped the real text and coverage went to 90.8%.

The demo tenants were at **100%** both before and after, because the generator uses the
map's own reason names. Only the real customer was ever affected, so no demo or regression
run could have surfaced it.

**Why:** the fallback is good behaviour (no appointment loses its reason) but it destroys
the obvious test. Reading the derived column tells you nothing about whether the map works.

**How to apply:** to judge mapping coverage, join `Silver.Appointment_Reason_Map` and count
what matches -- never read `Appointment_Reason`. V230's per-tenant 70% coverage guard is
that check; keep it as an onboarding gate for each new customer, whose reason text is their
own invention. Mapping a self-named reason is free: the fallback already produced that exact
string, so nothing downstream moves. Related:
[[read-the-schema-before-querying-it]], [[a-dq-rule-built-on-an-absence-is-wrong]],
[[calibrate-the-demo-tenant-against-live]], [[the-demos-bad-numbers-are-the-pitch]].
