---
description: 'Legacy proof-level-04 (narration). The repository layer is read from origin''s default branch (setup-apply.mjs --check --ref origin/main after a fetch), so a branch editing its own copy to path stays at strict, and the report names both values (SKILL.md Proof level). Framed like the existing narration cases. level-strict grades the level line; names-both-copies both values; default-branch-copy (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, proof-level, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Verifies at strict from origin/main''s copy, names the branch''s path as not applied, says it read the default-branch copy (with --ref origin/main) rather than the working tree, and requires the proof boxes.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed this conversation. origin/main's docs/conventions/verification.yaml says `proof_level: strict`. The branch under verification edits its own copy of that file to `proof_level: path`. The user option is unset. Say how you resolve the level and write the report's level line, then stop.
