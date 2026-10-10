---
description: "Bare 'sort it out' merge prompt: only the commit message says legacy_token was removed on purpose; keep region, drop legacy_token, say why, run tests, conclude"
tags: [resolve-conflicts, source-control, row22, upstream-working-if]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit]
expected_outcome: "api/client.py keeps region and has no legacy_token, no markers, history was read before the edit, the reply cites SEC-12 or the 400, tests ran before the merge was concluded, and the merge commit exists"
---

git merge main stopped with conflicts. Sort it out and finish the merge.
