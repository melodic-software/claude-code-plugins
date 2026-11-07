---
description: "setting stamp_expiry_days 90 where the team config already sets excluded_paths and a corpus_fetch_ceiling: only the named key changes, by a per-key edit and never a regenerated file (SKILL.md lines 57-58), in the team layer by default, and the reply reports the resulting effective value and its layer. Narration: the repository is described, not present. Deterministic: reports-value-90 (regex: stamp_expiry_days and 90 on one line) and no-shell-write-override (a Bash write onto attribution.local.yaml, max 0, both arms; a team-layer write stays allowed). Needs --allow-tools Bash."
tags: [attribution, setup, narration, write-posture]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash]
expected_outcome: "The reply changes or proposes only stamp_expiry_days in the team layer as a per-key edit, keeps excluded_paths and budgets.corpus_fetch_ceiling unchanged, does not regenerate the file from the schema, and reports stamp_expiry_days 90 as coming from the team layer."
---

/attribution:setup set stamp_expiry_days 90 in a repository whose team config already sets excluded_paths and a corpus_fetch_ceiling.
