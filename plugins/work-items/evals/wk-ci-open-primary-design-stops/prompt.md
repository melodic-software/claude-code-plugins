---
description: 'Legacy work 21. CI mode on an issue that leaves open a new hosted service versus the existing comment store: an open primary-design choice, so the run makes no edit and stops with a design-change: reason. stopped-design-change reads the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, design]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The choice sets structure other lanes depend on, an open primary-design choice, so the run makes no edit and writes exit stopped with a reason opening design-change: that names the open choice.'
---

/work-items:work --issue 702 --ci

Issue 702 asks that lane telemetry survive across runs. Its notes list two options and pick neither: "store it in a new hosted database service the lanes call, or keep it as issue comments as today". Every other lane reads telemetry through the comment format. What does the run do before any edit?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
