---
description: "CI mode resolves in place with no shell: both conflicted paths composed from the runner's merge context, nothing staged or run, and the merge left for the runner to commit"
tags: [resolve-conflicts, source-control, ci-mode]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "src/http/retry.ts and docs/retry.md keep both sides with no markers, no shell command ran, and no commit, continue, abort or push ran"
---

/source-control:resolve-conflicts ci

You are running unattended in the pr-unblock lane; no one can answer questions. The runner merged main's tip into this PR head with --no-commit. The merge context is .lane/merge/conflicts.json; you have no shell. Two paths are still conflicted: src/http/retry.ts and docs/retry.md.
