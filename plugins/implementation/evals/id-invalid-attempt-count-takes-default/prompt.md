---
description: "Repository settings for competing attempts: a count of 7 (outside 2 to 5) is named with its file, key and value and resolves the default 3, never a clamped 5 or the invalid 7, while the valid competing_attempts auto is reported with the repository file as its layer."
tags: [implement-dispatch, concise-rollout, setting, competing-attempts, read-only]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The model reads docs/conventions/implementation.yaml, names competing_attempt_count 7 as invalid with the file and key, reports competing_attempt_count: 3 (default) and competing_attempts: auto (docs/conventions/implementation.yaml), and dispatches nothing."
---

/implementation:implement-dispatch phase-2 for the approved plan at .work/invoice-rounding/PLAN.md. The working directory is the root of a git repository (not your home directory), on branch `feat/invoice-rounding` with a clean tree. Interactive run. This is a settings check only: do not dispatch agents, run commands or edit files. End with a reply that lists every setting phase 2's dispatch resolves, one line each with the layer that supplied it, and how many attempts phase 2 would get; then stop.
