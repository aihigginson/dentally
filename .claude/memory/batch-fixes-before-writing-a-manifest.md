---
name: batch-fixes-before-writing-a-manifest
description: "Collect related fixes into one release instead of cutting a manifest per discovery; V229-V235 in one afternoon, three of them fixing the previous one."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-10-22T12:25:39.228Z
---

The owner's words: *"You are rattling through a lot of releases. Can we try to batch up
fixes before we do the manifests."*

What triggered it: V229 through V235 in a single afternoon, with V230, V233 and V235 each
existing only to repair the release before it (an unmapped reason text, a missing surrogate
key, a stale allocation). Every one of those was a real fix, but each arrived as its own
manifest for the owner to read, approve and run -- and V229 itself needed three attempts
before it took.

**Why:** a manifest is not free. The owner reads the notes, runs it, waits for the loaders,
and reads the guard output. Cutting one per discovery turns a day's analysis into a queue of
deployments, and the ledger fills with FAILED rows that have to be explained later. Related
changes also deploy more safely together: V233 and V235 touched the same loader and the
same hash, so as one release there would have been one load and one set of guards.

**How to apply:** keep a running list of pending changes and write the manifest when the
batch is coherent, not when each fix is found. An undeployed manifest is the natural place
to accumulate -- fold the next fix into it rather than starting V+1. Say what is in the
batch and ask if anything else should go in before cutting it. Exceptions worth cutting
alone: something broken in front of the live customer, and a change whose blast radius the
owner needs to weigh on its own. Related: [[just-do-the-thing]],
[[lead-with-the-decision-not-the-argument]],
[[releases-touching-one-file-cannot-replay-individually]],
[[preprod-is-the-plan-when-revenue-allows]].
