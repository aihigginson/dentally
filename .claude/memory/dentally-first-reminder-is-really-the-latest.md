---
name: dentally-first-reminder-is-really-the-latest
description: Dentally's first_reminder_sent_at/_id carry the MOST RECENT reminder, not the first; only the reminders array is honest.
metadata:
  type: reference
---

The Dentally recall API's scalar reminder fields are mislabelled, and this was proven by GUID
rather than inferred:

* `first_reminder_id` equals the **newest** array element's id on **267 of 267** staged
  recalls that have any reminder — and the genuine first only on the 69 that have exactly one.
* `first_reminder_sent_at` equals `last_reminded_at` on every row, to sub-second rounding
  (Dentally rounds up when writing it, so a naive `LEFT(...,19)` comparison shows a 1-second
  difference on some rows — that is the same value, not a counter-example).
* `second_reminder_sent_at` and `second_reminder_type` and `second_reminder_id` are **never
  populated**, for any row.

The `reminders` array is the only honest source. It is **newest-first**, so ordering by date
ASC is what makes sequence 1 the genuine first chase — using the array index numbers them
backwards. `times_contacted` equals the array length **exactly** on all 292 staged rows,
every value 0 to 6, so it is a reliable count and a reliable index. Each element carries
type (SMS/Email), id, date with offset, and `template_name` — which even names the position,
e.g. "- OAB Dental recall 2".

**Why:** this made "First Reminder Sent Date" show the most recent chase for three months,
and V247's second-reminder fallback (from `last_reminded_at`) then reproduced the same value
— so the two columns read identically on all 5,777 of Maple's multi-reminder recalls. V247's
checks validated `$[0].date == last_reminded_at` and never compared `first_reminder_sent_at`
to the array, which is exactly where the error was.

**How to apply:** read reminder dates from `Silver.Recall_Reminders` (V249), never the Bronze
scalars. `Recall_Status` deliberately keys off `Times_Contacted`, not the date keys, because
recalls ingested before the array was landed have no decoded reminders and would lose their
'1st/2nd Reminder' labels. Related: [[bronze-recalls-cannot-be-dropped]],
[[a-dq-rule-built-on-an-absence-is-wrong]], [[read-the-schema-before-querying-it]].
