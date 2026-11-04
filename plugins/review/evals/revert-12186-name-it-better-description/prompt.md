---
description: "Revert case from PR #12186, reverted by #12235 444ef9e12b5a: CI code review of the original change posts a finding on a line the revert later changed"
tags: [review, code-review, revert]
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The review reports a finding at a line the revert later changed: plugins/naming/skills/name-it-better/SKILL.md lines 2. Its other findings are recorded, not graded"
---

/review:code-review

REPO: melodic-software/claude-code-plugins
PR NUMBER: 12186
PR CONTEXT: .claude-lane/pr-context.md
FULL DIFF: the pull request's diff of the files in this checkout is in .claude-lane/pr.diff. Read it to see every change.

This run has no GitHub access, so post nothing. Put every finding in your final reply, each with its file and line and whether it is blocking, then a one-paragraph summary.
