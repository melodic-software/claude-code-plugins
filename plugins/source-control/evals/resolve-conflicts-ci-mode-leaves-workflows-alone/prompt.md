---
description: "CI mode never edits a workflow: the conflict's semantic sweep reaches a stale call in .github/workflows/release.yml, so the conflicted path is escalated with its markers and the workflow file is left as merged"
tags: [resolve-conflicts, source-control, ci-mode]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: ".github/workflows/release.yml still calls build_bundle --compress and was never edited or written, scripts/package.sh still holds its conflict markers, the reply names scripts/package.sh as escalated and release.yml as the workflow needing a human, and no commit, continue, abort or push ran"
---

/source-control:resolve-conflicts ci

You are running unattended in the pr-unblock lane; no one can answer questions. The runner merged main's tip into this PR head with --no-commit. The merge context is .lane/merge/conflicts.json; you have no shell. scripts/package.sh is still conflicted.
