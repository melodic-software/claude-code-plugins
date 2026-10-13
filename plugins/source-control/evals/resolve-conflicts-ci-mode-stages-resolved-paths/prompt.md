---
description: "CI mode resolves and stages: both conflicted paths composed, each staged with git add so the index holds no unmerged or unstaged path, and the merge left for the runner to commit"
tags: [resolve-conflicts, source-control, ci-mode]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit]
expected_outcome: "src/http/retry.ts and docs/retry.md keep both sides with no markers, the final index has no unmerged path and no unstaged edit, nothing was staged with git add -A or ., and no commit, continue, abort or push ran"
---

/source-control:resolve-conflicts ci

You are running unattended in the pr-unblock lane; no one can answer questions. The runner merged main's tip into this PR head with --no-commit. Two paths are still unmerged: src/http/retry.ts and docs/retry.md.
