---
description: "CI mode makes room elsewhere for a line the spec needs: SKILL.md is one line over its cap after address-feedback added a criterion's line, and a three-line paragraph no criterion names can be tightened, so check-skills is fixed with every quoted line kept"
tags: [pull-request, source-control, ci-mode]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Bash, Edit]
expected_outcome: "skills/run-validity/SKILL.md is at most 10 lines and still holds each list line the done-when items quote, scripts/check-skill-size.sh is byte-identical, the check ran, no git write ran, and the reply says check-skills: fixed"
---

/source-control:pull-request ci --ci

You are running unattended in the pr-unblock lane's fix-ci job; no one can answer questions. The runner's context file is .git/fix-ci-context.json. The working tree is the pull request's head, and the check-skills check failed on it.
