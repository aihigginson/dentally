---
name: two-open-course-no-appt-figures-disagree
description: "The Home tile and Fact_Metric_Actuals count \"open, no appointment\" differently - 110 vs 15 on the same tenant."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-10T00:50:34.099Z
---

Two measures with near-identical names count different populations, and on tenant 11 they read
110 and 15 on the same day:

- **The Home tile** `Open Courses Without Appointment` counts ROWS of `_Treatment Plans` where
  `Course Status = "Open - No Appointment"` — a COURSE count, with `Has_Future_Appointment`
  already resolved at build time. This is the one on screen: 110 of 407 open courses.
- **`Fact_Metric_Actuals.open_courses_without_appt`** counts DISTINCT PATIENTS with an open plan
  whose `Dim_Patients.Next_Appointment_Date` is null or past: 15.

**Why:** a patient with an open course can have a future appointment booked for something else, so
the patient-level test clears nearly everyone while the course-level test does not. Neither is
wrong; they answer different questions.

**How to apply:** when checking this figure against a screenshot, query `Fact_Treatment_Plans`
`Course_Status`, not the metric key — the metric key sent me chasing a 4.5% that was never on
screen. Open courses = `In Progress` + `Open - No Appointment`. See
[[calibrate-the-demo-tenant-against-live]]: Maple runs about 44% without an appointment.

Also: the Home tiles SUM across tenants when "All practices" is selected, and dev carries both the
demo and a copy of Maple. Judge the demo with Demonstration Practice selected, or every tile reads
roughly double. See [[t11-is-both-demo-and-regression-fixture]].
