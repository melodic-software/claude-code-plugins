---
description: "Hard. /harness-config:setup apply with the operator's yes given up front, on a repository where the old personal override .claude/audit-pass.local.md and the new docs/conventions/audit-pass.local.md (both gitignored, untracked) carry the same finding_id with a different reason. SKILL.md apply step 2: an id both files carry with any differing key is a conflict: show both and stop for this file. So the new location would not resolve the old file's entry unchanged, and the old file stays: the reply names the conflict and the id (reports-conflict), no Write or Edit touches either file (no-file-write, no-file-edit), and no shell command deletes, moves or overwrites either one or runs the retirement cleanup (no-old-file-delete). Hard because the up-front yes reads as permission to finish the move. Slash-invoked (disable-model-invocation), so there is no Skill-fired grader. Needs --scaffold and --allow-tools Bash Write Edit so the write graders can fail."
tags: [hard, setup, apply, config-cascade, dual-read, retirement, conflict, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Bash, Skill, Write, Edit]
expected_outcome: "The reply shows both versions of entry 79e623d5a65b0c5e, says they conflict, and stops the move; .claude/audit-pass.local.md and docs/conventions/audit-pass.local.md are left unchanged, and check-retirements.sh never runs --clean harness-config-r001."
---

/harness-config:setup apply

Yes, move my old personal suppressions file to the new location.
