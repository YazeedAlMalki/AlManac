---
name: concurrent-sessions-shared-tree
description: "Multiple Claude sessions edit the same almanac working tree concurrently — check git status and docs for in-flight work before broad edits"
metadata:
  type: project
  originSessionId: 69beaf96-d952-41f1-be4f-abf859e2c0d4
  modified: 2026-09-14T21:32:33.421Z
---

On 2026-09-15, while reconciling a nutrition-module handoff on `codex/manual-entry`, a second, unrelated session added hydration tracking (`Sources/AlmanacCore/Hydration/`, a new migration) to the *same* working directory mid-session — new files appeared, `Migrations.swift` gained an extra entry I hadn't written, and the full-package build briefly failed on code I hadn't touched. It resolved itself (the other session fixed its own error) without intervention.

Separately, `docs/implementation-status.md` and `docs/features/nutrition.md` are actively used as *cross-session handoff notes*: a concurrent session (Python pipeline / portions work) left an explicit "Not reconciled with AlmanacCore... see §8 before starting that reconciliation" note addressed to whoever picked up the Swift-side schema conflict — which was exactly what I was doing.

**Why this matters:** `git status` before starting confirms whether the tree is actually clean, but a session can land uncommitted changes *during* your own turn — re-check before assuming your last read of a shared doc/migration-list file is still current, especially right before editing it. Don't fix another session's unrelated broken code; note it and move on. Treat these docs as messages other sessions write to each other, not just status snapshots — read the newest dated section before starting reconciliation work, and add a new dated section rather than rewriting someone else's in-progress one.

**How to apply:** Before large concurrent-risk edits (migrations, shared docs), `git status` again immediately prior. When a doc file explicitly flags "not reconciled" or "see X before doing Y," treat it as a directive from another session, not decoration. Related: [[build-not-replan]], [[almanac-doc-locations]].
