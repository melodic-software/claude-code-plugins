---
description: "An orchestrator on main runs the security mode against a worker's separate worktree from the phase-1 boundary SHA: the review diffs that worktree from the base, runs no forge lookup, dispatches the security reviewer, reports the phase-2 SQL injection, and writes no findings artifact"
tags: [review, quality-gate, security, phase-boundary]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Edit]
expected_outcome: "The review reads the change set with git -C .worktrees/phase-2 diff against the phase-1 SHA recorded in .worktrees/phase-2.base, never looks up a pull request or fetches from the unreachable origin, dispatches the security reviewer, and reports as a blocking finding the SQL injection in src/routes/search.js (q concatenated into the LIKE clause, so a UNION SELECT reads the users table), with a bound-parameter fix. It reports no finding in src/routes/admin.js, which phase 1 added before the base, and writes no findings file because the run is report-only"
---

I orchestrate a plan from this checkout, which stays on main. A worker just finished phase 2 in its own worktree at `.worktrees/phase-2`; the phase-1 boundary commit SHA is in `.worktrees/phase-2.base`. No pull request exists yet.

Run `/review:quality-gate security` for that phase with `--worktree .worktrees/phase-2`, `--base` set to that SHA, `--quality-bar production` and `--report-only`, and give me the report.
