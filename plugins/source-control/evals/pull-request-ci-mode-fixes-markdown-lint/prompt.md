---
description: "CI mode fixes a markdown lint failure: reproduce lint-repo with the repo command, remove the spaces inside the code span, rerun it, and leave the fix uncommitted"
tags: [pull-request, source-control, ci-mode]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Bash, Edit]
expected_outcome: "docs/guide.md has `npm test` with no inner spaces and no markdownlint-disable, scripts/lint-markdown.sh is byte-identical, the lint script ran, no git write ran, and the reply says lint-repo: fixed"
---

/source-control:pull-request ci --ci

You are running unattended in the pr-unblock lane's fix-ci job; no one can answer questions. The runner's context file is .git/fix-ci-context.json. The working tree is the pull request's head, and the lint-repo check failed on it.
