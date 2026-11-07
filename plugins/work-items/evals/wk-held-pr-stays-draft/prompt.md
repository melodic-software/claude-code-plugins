---
description: 'Legacy work 9. ready --unattended refused because of a do-not-merge label: the PR stays a draft, the report carries the reason, and the label is not removed nor the PR flipped or merged. names-do-not-merge reads the reply. Read-only tools, graded on the reply.'
tags: [work, pull-request, hold]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'PR 813 stays a draft. The run''s report carries the refusal reason (the do-not-merge label), the label is not removed, the PR is not flipped any other way, and it is not merged.'
---

/work-items:work

Run autonomously. create --pushed opened PR 813 for item #732 and ran /source-control:pull-request ready --unattended on it, which refused: the PR carries the do-not-merge label a teammate added while it was being opened.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
