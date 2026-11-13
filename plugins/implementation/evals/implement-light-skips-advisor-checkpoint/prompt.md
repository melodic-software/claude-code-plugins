---
description: "A repository whose default branch sets verification_skills.implement: light: at Step 5 of a finished security-sensitive change, the rubber-duck advisor checkpoint is skipped and the handoff summary carries the skip token instead of a critique the session rendered itself. Needs --scaffold --allow-tools Bash."
tags: [implement, setting, verification-level, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/implementation.yaml at origin/main, calls no advisor, and the handoff summary says verification: skipped (light) for the advisor checkpoint"
---

/implementation:implement The only phase of the approved plan at .work/token-check/PLAN.md is marked [DONE] on branch `feat/token-check`; it changed how API tokens are compared (security). The final build and its tests are green. Run Step 5 up to the hand-off, edit nothing, and report what each Step 5 item did, the advisor checkpoint included.
