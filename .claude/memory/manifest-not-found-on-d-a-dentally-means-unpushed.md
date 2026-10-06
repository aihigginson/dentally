---
name: manifest-not-found-on-d-a-dentally-means-unpushed
description: "Manifest not found: D:\\a\\dentally\\dentally\\... from a prod deploy means the commit was never pushed, not a broken path."
metadata: 
  node_type: memory
  type: project
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-27T07:30:50.074Z
---

`D:\a\dentally\dentally\` is the **GitHub Actions runner** working directory. So
`Manifest not found: D:\a\dentally\dentally\Releases\Vnnn__....manifest` from the prod
deploy workflow means the workflow checked out `origin/dev` and the manifest is not in it —
the release was committed locally and never pushed. The path is not wrong and the manifest
is not malformed.

**Why:** on 2026-09-27 I committed V188 locally, said prod was ready, and the user's prod
deploy failed with exactly that line. I had read it as a path problem for a moment before
noticing `D:\a\` is not a path that exists on this machine.

**How to apply:** `git push origin dev` **before** telling the user a release can be
deployed through Actions. If they have already hit the error, pushing is the whole fix —
re-run the workflow, nothing needs editing. A local
`.\Scripts\Deploy.ps1` run does not need the push, which is why dev can be green while the
prod workflow cannot see the file at all — see
[[prod-warehouse-deploy-from-the-laptop]].
