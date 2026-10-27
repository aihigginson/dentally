---
name: demo-screens-are-poked-for-the-marketing-page
description: "The blind-spot page's associate screen needs DEV tenant 11 diary data poked to tell its story; a nightly rebuild silently undoes it, and diary_fill lives in two tables."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-27T18:49:43.811Z
---

**The screenshots on `Website/blind-spot.html` need the DEV demo data reshaped first.** The My
Data figure's argument is an associate booked past the hours she works. The seeded data does not
produce that, so before re-shooting, poke tenant 11 (Demonstration Practice), Amara Singh
(`pk_Practitioner` 71):

- `Gold.Fact_Metric_Actuals` — `diary_fill` Numerator, drives the KPI **tiles**
- `Gold.Aggregate_Site_Patient_Practitioner_Daily` — `Appointment_Hours`, drives the **strip**
- `Gold.Aggregate_Site_Practitioner_Current` — `Days_Until_Next_30_Free`, the tile that FLAGS it

==> `diary_fill` LIVES IN TWO TABLES CARRYING IDENTICAL NUMBERS. <== So matching values prove
nothing about which one a visual reads. Poking only `Fact_Metric_Actuals` changed nothing on
screen even after a real refresh, because the strip reads the aggregate. Poke both.

==> days-to-next-free MUST MOVE WITH THE FILL. <== It is the overbooking flag. Leaving it at 1
has the screen contradict itself: every day booked past 100%, free slot tomorrow. The owner
wants it **10 or more** — that is the story.

**The model is Import.** Nothing appears until a refresh runs AFTER the write. A real refresh is
30-45s; see [[nightly-model-refresh-reports-false-success]]. Scripts in the session scratchpad:
`poke_diary.sql`, `poke_diary2.sql`, `poke_days.sql`, `refresh_dev_model.py`.

**It is temporary and that is accepted.** Both Gold tables are full rebuilds, so the next
nightly restores the real figures. The screenshots are already taken by then.

**Shoot the DEMO app, never `app.analytically.info`** — that opens on Maple Dental, whose real
revenue and patient counts must never reach a public page. `demo.analytically.info` is the one.

Side effect to watch: lifting one practitioner moves the practice figure too. Diary fill went
79.6% → 81.5%, crossing its 80% target to green, which contradicts "the diary is under-filled"
in the page's four-line summary. Re-shoot Home when you poke.

The page's pins are percentages of the image and its captions quote figures off the
screenshots, so a re-shoot is never just a file swap — see
[[a-detail-table-needs-a-column-not-a-measure]] for the general habit of checking what else
reads a thing before changing it.
