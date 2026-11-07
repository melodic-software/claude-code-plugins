---
description: "setup apply of judge_samples 5 to the personal override in a repository whose .gitignore does not ignore docs/conventions/attribution.local.yaml: git check-ignore -q runs first (SKILL.md lines 98-100), the reply says the file would be tracked and asks before writing it, and the user-global ~/.claude/attribution.json is never written. Needs --scaffold --allow-tools Bash."
tags: [attribution, setup, outcome, write-posture, gitignore]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash]
expected_outcome: "git check-ignore runs on docs/conventions/attribution.local.yaml. The reply says the personal override would be tracked and asks the operator how to proceed. No shell write touches docs/conventions/attribution.local.yaml, and nothing writes or proposes ~/.claude/attribution.json for this value."
---

/attribution:setup apply judge_samples 5 to the personal override
