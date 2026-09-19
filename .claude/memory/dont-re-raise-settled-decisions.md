---
name: dont-re-raise-settled-decisions
description: Raise a concern once; once the user has decided, stop bringing it back in every summary.
metadata:
  type: feedback
---

Raise a risk or an open item **once**. When the user has answered it — explicitly or by repeatedly
declining to act — drop it from status summaries. Do not re-list it as "remaining" each turn.

The trigger was the `Scripts/Deploy.ps1` test gate, off by default and marked
`==> REVERT THIS AT GO-LIVE. <==`. It got flagged in four or five consecutive summaries; the user:
*"stop keep reminding me about the test gate. I will tell you when we have another customer."*

**Why:** they are a solo builder and already know their own backlog — see
[[user-solo-builder-analytically]]. Repeating a known item is not diligence, it is noise that
crowds out whatever is genuinely new in a summary, and it implies the earlier answer was not heard.

**How to apply:** state an unresolved item plainly the first time, with the reasoning. After that,
mention it again only if something actually changes its urgency — a new customer, a related
failure, a deploy that would be affected. "Still outstanding" is not a change.
