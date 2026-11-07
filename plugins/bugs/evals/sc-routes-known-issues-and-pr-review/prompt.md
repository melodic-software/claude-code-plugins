---
description: "Two requests that are not a proactive hunt: what is already known to be broken in Claude Code, and a pre-merge diff review. The reply routes the first to harness-ops:known-issues and the second to review:code-review or review:security-review, names bugs:write as the lane for an observed defect, and dispatches no hunter. Scan SKILL.md description (Skip when reviewing a diff; 'scan repo for issues' is harness-ops:known-issues; 'file a bug' the user observed is bugs:write)."
tags: [bugs, scan, routing, outcome, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The reply sends the known-issues question to harness-ops:known-issues, the PR diff check to review:code-review (or review:security-review), says bugs:write handles a defect the user already observed and /bugs:scan hunts unobserved bugs in resting code, and starts no hunt (no Agent call)."
---

Scan the repo for issues: I want to know what's already known to be broken with Claude Code itself, and also please double-check the diff on my open PR before I merge it.
