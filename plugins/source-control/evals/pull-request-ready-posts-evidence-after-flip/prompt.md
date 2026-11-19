---
description: After the ready flip, ready posts the evidence comment for the confirmed head (skills/pull-request/evals/evals.json entry 64, ready-posts-evidence-after-flip-for-confirmed-head, run against an offline forge)
tags: [pull-request, source-control, routine]
plugins: ["../..", "gh-forge-path"]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: After gh pr ready, ready runs its evidence step for the confirmed head and posts one evidence comment through gh pr comment with the publishable capture attached, and the report has an evidence line saying it was created
---

PR 655 is an open draft on this branch. Its change touched the cart page, the verification on the current head passed and was confirmed, and the end-to-end run earlier in this session wrote `evidence/e2e-summary.json` on this head. Flip it to ready for review with `--evidence evidence/e2e-summary.json`.

I am here for this run.
