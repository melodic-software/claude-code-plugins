---
description: "Legacy morning-brief 9. Reaches SKILL.md 'What each section reports' (Stuck): an item is listed once its newest labeled event for a queue label is older than --stuck-days (default 7), --stuck-limit (default 20) caps the lines with PARTIAL past it, and the section only lists. names-stuck-limit reads the reply; meets-expectations judges the rest. Bash is listed only so SKILL.md's pre-computed context lines load; needs --allow-tools Bash. Graded on the reply."
tags: [work-items, morning-brief, routine, stuck]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The Stuck section lists open issues and PRs whose newest labeled event for a queue label is older than --stuck-days (default 7), oldest first, one line each with number, title, label and days in stage. The two-day-old item is under the threshold. --stuck-days moves the threshold and --stuck-limit (default 20) caps the lines, saying PARTIAL past it. The section only lists; it never moves or relabels an item."
---

/work-items:morning-brief

Why does the Stuck section of the morning brief list a PR labeled needs-human nine days ago but not an issue labeled status: ready two days ago, and how do I list fewer or more?

The text below the command is the operator's question, not flags. No tracker, forge or shell is reachable in this session, so make no such call: answer from what this skill states.
