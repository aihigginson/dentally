---
name: commit-at-each-working-point
description: "Commit as each piece of work lands, not at the end of the session -- the deploy runner reads git, so uncommitted files fail or silently deploy stale versions."
metadata:
  type: feedback
---

A full day's work sat uncommitted until the owner hit "Manifest not found:
D:\a\dentally\dentally\Releases\V236...". The manifest existed only on the laptop. Worse
than the error: **10 of its 14 DEPLOY targets were also uncommitted** -- four untracked
(would have failed the same way) and six modified (would have silently deployed LAST WEEK'S
procedure bodies into a warehouse that had just gained this week's columns).

The owner's words: *"absolutely... That is how we have been working for months. I assumed
you'd done it."*

**Why:** `Scripts/Deploy.ps1` run locally reads from disk, so everything passes on the
workstation and the gap only appears on the Actions runner -- at the moment of a prod
deploy. And a half-committed release is the specific shape that deploys a new schema
against old code without erroring.

**How to apply:** commit when a piece of work is finished and verified, not at the end of
the session. Before ANY release, check `git status` against the manifest's DEPLOY list --
every target must be committed, not just the manifest. Related:
[[manifest-not-found-on-d-a-dentally-means-unpushed]],
[[releases-touching-one-file-cannot-replay-individually]], [[just-do-the-thing]].
