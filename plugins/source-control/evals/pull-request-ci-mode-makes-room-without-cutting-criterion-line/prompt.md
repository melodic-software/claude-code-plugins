---
description: "CI mode makes room under a line cap without cutting a line the linked issue's criteria need: SKILL.md is over check-skills' cap, a history paragraph no criterion names can go, and the line the last address-feedback round added stays, so check-skills is fixed"
tags: [pull-request, source-control, ci-mode]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Bash, Edit, Write]
expected_outcome: "skills/run-review/SKILL.md is within the 10-line cap and still holds the heading and every line a criterion names, the address-feedback line included, scripts/check-skills.sh is byte-identical to the PR head, the check ran before and after the fix, no git write ran, and the reply reports check-skills fixed"
---

/source-control:pull-request ci --ci

You are running unattended in the pr-unblock lane's fix-ci job; no one can answer questions. The runner's context file is .git/fix-ci-context.json. The working tree is the pull request's head, and the check-skills check failed on it.
