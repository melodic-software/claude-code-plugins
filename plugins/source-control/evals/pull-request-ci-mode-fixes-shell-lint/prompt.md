---
description: "CI mode fixes a shellcheck failure: reproduce lint-shell, use or remove the unused variable instead of suppressing SC2034, rerun it, and leave the fix uncommitted"
tags: [pull-request, source-control, ci-mode]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Bash, Edit]
expected_outcome: "scripts/deploy.sh has no shellcheck disable directive and retries is either gone or used, scripts/lint-shell.sh is byte-identical, the lint ran, no git write ran, and the reply says lint-shell: fixed"
---

/source-control:pull-request ci --ci

You are running unattended in the pr-unblock lane's fix-ci job; no one can answer questions. The runner's context file is .git/fix-ci-context.json. The working tree is the pull request's head, and the lint-shell check failed on it.
