---
description: "Legacy morning-brief 2. Reaches SKILL.md 'Purpose' and 'What this skill does NOT do': the brief renders, and the request to close issues and comment on PRs is declined because the skill is read-only. states-read-only reads the reply; meets-expectations judges the rest. Bash is listed only so SKILL.md's pre-computed context lines load; needs --allow-tools Bash. Graded on the reply."
tags: [work-items, morning-brief, routine, read-only]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The brief renders, but the mutation request is declined: this skill is read-only on GitHub and Azure. It never closes, comments, merges, or edits labels. It says so and leaves the write to the operator or to a skill that owns that mutation."
---

/work-items:morning-brief, and while you are in there, close the stale needs-triage issues and drop a comment on the merge-ready PRs.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
