---
description: "Recall case from PR #7617, a confirmed lane miss: CI code review of the new be-ambitious skill finds that its SKILL.md frontmatter (lines 1-8) has no argument-hint although the skill reads a request typed after the command"
tags: [review, code-review, recall]
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The review reports a finding in the frontmatter of plugins/discipline/skills/be-ambitious/SKILL.md (lines 1-8) that it declares no argument-hint, although the body says the request is the text typed after the command, so the command shows no hint for its argument. Its other findings are recorded, not graded"
---

/review:code-review

REPO: melodic-software/claude-code-plugins
PR NUMBER: 7617
PR CONTEXT: .claude-lane/pr-context.md
FULL DIFF: the whole pull request's diff is in .claude-lane/pr.diff. Read it to see every change.

This run has no GitHub access, so post nothing. Put every finding in your final reply, each with its file and line and whether it is blocking, then a one-paragraph summary.
