---
name: three-things-are-called-open-plans-or-courses
description: "Open Plans", "open_courses" and "Open Courses Without Appointment" are three different definitions in three different places — check which one before changing anything.
metadata:
  type: project
---

Three similarly-named things, three definitions, three homes:

| name | where | definition |
|---|---|---|
| **Open Plans** | `Aggregate_Site_Practitioner_Current` → `PBI.List Practitioners` | `Course_Status = 'Open - No Appointment'` (V250; was `IN ('In Progress','Open - No Appointment')`) |
| **open_courses** (KPI) | `Gold.usp_Load_Fact_KPI_Snapshot`, block A1 | DATE-based — started ≤ D, not ended, not completed. **Never reads `Course_Status` at all.** |
| **Open Courses Without Appointment** (KPI) | DAX measure on `_Treatment Plans` in `PBI_Dentally.csx` | `Course Status = "Open - No Appointment"` |

Plus `open_courses_value` and `open_courses_without_appt_value`, which mirror the two KPIs.

**Open Plans is a WORKLIST column, not a KPI.** It answers "what does this practitioner need
to chase", which is why V250 narrowed it to courses with nothing booked — `In Progress` is a
course already underway with an appointment in the diary. The KPI pair is untouched by that
and still means what it always meant; the owner was explicit that both KPIs are wanted as
they are.

**Open Plans appears on TWO screens** — Day Book, and Schedule > Utilisation, in the pivot
beside Cancellations To Rebook / DNAs To Rebook / Recalls To Action / Days Until Next 30
Free. Both bind the one column, so they cannot diverge without splitting it. Settled: Schedule
follows the Day Book.

**Why:** on 2026-10-27 I was asked to narrow the Day Book's Open Plans and had to be stopped
to check I had not broken the KPIs. I had not — but only by luck of where the code lives, and
my first grep for consumers matched Clinical and My Data, which actually bind
`_Measures.Open Courses Value` and were never affected.

**How to apply:** before changing anything called open plans/courses, establish WHICH of the
three. A `Course_Status` edit cannot touch `open_courses`; a `Fact_KPI_Snapshot` edit cannot
touch the Day Book. And remember the worklist rule also lives in the detail page's own
filters — [[recalls-to-action-lives-in-three-places]]. Related:
[[two-open-course-no-appt-figures-disagree]], [[day-book-grid-reads-columns-not-measures]].
