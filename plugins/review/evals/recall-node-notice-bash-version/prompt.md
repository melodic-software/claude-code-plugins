---
description: "Recall case from PR #5997, fixed forward by #6131: CI code review of the node-notice SessionStart row finds that ${BASH_VERSION:+exit} at plugins/eol-normalizer/hooks/hooks.json:9 never exits under a /bin/sh that is not bash, so the row falls through to powershell"
tags: [review, code-review, recall]
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The review reports a finding at plugins/eol-normalizer/hooks/hooks.json line 9: the command's POSIX half stops with ${BASH_VERSION:+exit}, but a /bin/sh such as dash sets no BASH_VERSION, so the command goes on to run powershell, which is missing on Linux and errors at every session start. Its other findings are recorded, not graded"
---

/review:code-review

REPO: melodic-software/claude-code-plugins
PR NUMBER: 5997
PR CONTEXT: .claude-lane/pr-context.md
FULL DIFF: the whole pull request's diff is in .claude-lane/pr.diff. Read it to see every change.

This run has no GitHub access, so post nothing. Put every finding in your final reply, each with its file and line and whether it is blocking, then a one-paragraph summary.
