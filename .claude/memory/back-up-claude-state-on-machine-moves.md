---
name: back-up-claude-state-on-machine-moves
description: Claude's own state lives outside OneDrive and must be explicitly included in migration/setup docs.
metadata:
  type: feedback
---

When writing setup, migration, or runbook docs, treat **Claude Code's own state** as an
asset to be restored — not just the project's code and secrets.

**Why:** On the 2026-09-06 move to a new PC, `SETUP.md` catalogued OneDrive, GitHub,
Fabric, Key Vault and browser logins, and was correct that "you cannot lose data by
replacing the machine" — but it omitted `~/.claude`, which is in the Windows user
profile and therefore *not* covered by OneDrive. Every memory was lost. The user
raised this directly: the one thing that did not survive the move was Claude itself.

**How to apply:** Memories now live in `<repo>/.claude/memory/` (OneDrive + git), with
`~/.claude/projects/<slug>/memory` as a directory junction pointing at it — so writing
a memory commits it to a synced, versioned location automatically. The restore steps
are `SETUP.md` §8. Note the `<slug>` is derived from the project's full path, so it
changes if the repo moves; the junction must then be recreated. See
[[user-solo-builder-analytically]].
