---
description: 'Legacy triage 10. The attention view drops an issue titled `Lane telemetry: work-loop` before bucketing even though it carries needs-triage, lists the two ordinary unlabeled bug reports, and leaves the telemetry issue untouched. lists-both-bugs and telemetry-not-listed read the reply. Read-only tools, graded on the reply.'
tags: [triage, attention-view, lane-telemetry, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The attention view lists #31 and #32 under unlabeled and nothing else; #900 is excluded as lane infrastructure by its telemetry title before bucketing, and is not relabeled, commented on or closed.'
---

/work-items:triage

The repo has three open issues: #900 titled `Lane telemetry: work-loop` carrying `needs-triage`, plus two ordinary unlabeled bug reports, #31 'CSV export drops the header row' and #32 'Ledger totals are off by one cent'.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
