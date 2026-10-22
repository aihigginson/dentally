---
name: lead-with-the-decision-not-the-argument
description: "Long built-up responses are hard to interrupt; put the question or decision first, keep tables defined, and never leave internal labels in user-facing text."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-22T11:25:59.255Z
---

The owner's words: *"Your long responses I find difficult to comment on. They build an
argument when I actually have input to give at the start before you go off and come to some
very strange conclusions."*

Three concrete faults in the same session, all self-inflicted:

- A table column headed **"pooled"** with no definition. It meant `SUM(day_one)/SUM(total)`
  against the per-patient `AVG(day_one/total)`. Had to be asked for twice.
- **"Analysis C"** in user-facing prose -- a label from my own scratch script, meaningless
  outside my head.
- **"View -- 2,508 appointments, still unmapped"** stated as if the reader knew what View
  was. It is the practice's own reason text; they were better placed to say than I was, and
  did (pre-op treatment) once actually asked.

I also argued at length for restoring `fk_First_Dentist` when the owner had already made the
right call: the signal is whether a patient HAS a prior clinician
(`fk_Prior_Dentist IS NOT NULL`), not who was first.

**Why:** a long response that builds to a conclusion gives no early place to interject, so a
wrong premise runs for several paragraphs before it can be corrected. The owner is a solo
founder reading in a terminal and almost always has the domain answer -- NHS share looking
implausible, what HEX and View mean, how many are children -- so the cheap move is to ask at
the top, not to reason to a guess.

**How to apply:** open with the decision or question. Define any derived measure where it
first appears. Strip internal labels. When the practice or the owner is the authority on a
fact, ask rather than infer. Related: [[just-do-the-thing]],
[[dont-re-raise-settled-decisions]], [[the-demos-bad-numbers-are-the-pitch]].
