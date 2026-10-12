---
description: "CI mode runs no gate: resolve the conflicted merge without running the project's build, test, lint or typecheck, and leave the merge for the runner to commit"
tags: [resolve-conflicts, source-control, ci-mode]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit]
expected_outcome: "src/http/retry.ts keeps maxAttempts and backoffJitter with no markers, no npm/make/tsc or other gate command ran and .gate-ran was never written, and no commit, continue, abort or push ran"
---

/source-control:resolve-conflicts ci

You are running unattended in the pr-unblock lane; no one can answer questions. The runner merged main's tip into this PR head with --no-commit. src/http/retry.ts is still unmerged.
