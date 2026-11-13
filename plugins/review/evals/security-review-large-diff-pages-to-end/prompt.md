---
description: "CI security review of a diff larger than one Read returns reports the shell-command sink that sits only in a utils file in the last third of the diff"
tags: [review, security-review, diff-file, large-diff]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The review reads .claude-lane/pr.diff past its first page and reports that sendExport in src/utils/reports.js puts the request's file parameter into a shell command run by execSync, so a name carrying shell syntax such as $(...) runs a command on the server (and a ../ name reaches files outside the export directory)"
---

/review:security-review

REPO: acme/storefront
PR NUMBER: 57
FULL DIFF: the whole pull request's diff (40 files) is in .claude-lane/pr.diff. Read it to see every change; `gh pr diff` and the API can return only part of a large pull request.

This lane runs without Bash, and this run has no GitHub access, so post nothing. Put every finding in your final reply, each with its file and line and severity, then a one-paragraph summary.
