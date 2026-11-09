---
description: 'Legacy triage 2. A thin external bug report is reproduced from the reporter''s steps before anyone is asked about the fix; with too little detail it is parked at needs-reporter-info with the structured needs-info comment. needs-info reads the reply. Read-only tools, graded on the reply.'
tags: [triage, verification, needs-info]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply attempts reproduction from the report before any interview, reports the result as confirmed, failed or insufficient detail, and on insufficient detail applies needs-reporter-info with a structured comment of fact-seeking questions, each saying what its answer decides, and a list of what the pass settled.'
---

/work-items:triage 17

Item #17 is an external bug report claiming exports silently drop rows; the description is thin.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
