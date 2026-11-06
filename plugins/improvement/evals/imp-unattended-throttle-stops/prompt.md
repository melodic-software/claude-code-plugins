---
description: "Legacy improve case unattended-skips-upstream-and-throttles, throttle half. Narration: no source-control plugin loads and the forge is unreachable, so the prompt gives the open improve pull requests as facts (three, the throttle limit). The run asks nothing (no-ask-tool, no-question-in-reply), stops and says it is at the throttle limit (stops-at-throttle), makes no edit, branch, commit, push or pull request (no-edit, no-branch-commit-or-pr), and reaches for no upstream guidance (no-research-skill, no-web-fetch, no-web-search). The below-throttle path, one pull request created with --draft, an issue-linkage line and no merge, needs the forge and is held. Needs --scaffold and --allow-tools Bash Edit WebFetch WebSearch so the must-not graders can fail; without WebFetch and WebSearch on the command line, no-web-fetch and no-web-search cannot fail."
tags: [improve, unattended, throttle, narration, no-network]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Edit, Bash, AskUserQuestion, WebFetch, WebSearch]
expected_outcome: "The run asks no question, counts the three open improve pull requests, stops at the limit of 3 with a short report, and edits, branches, commits, pushes and fetches nothing."
---

Run /improvement:improve --unattended on plugins/example/. This is a scheduled run with no user present.

Facts for this run, take them as given: the forge is unreachable from this sandbox, and the open pull requests in this repository whose head branches match `^[a-z]+/improve-` are #12 `fix/improve-retry-quoting`, #15 `refactor/improve-report-names` and #19 `docs/improve-setup-steps`.
