---
description: "Legacy morning-brief 6. Reaches SKILL.md 'Cross-references' and 'What this skill does NOT do': token burn rate and hook latency are local telemetry this skill does not read, so the request routes to /harness-ops:observability and no local-telemetry section is added. routes-to-observability reads the reply; meets-expectations judges the rest. Bash is listed only so SKILL.md's pre-computed context lines load; needs --allow-tools Bash. Graded on the reply."
tags: [work-items, morning-brief, routine, routing]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Those come from locally captured telemetry (OTEL store, hook-event JSONL, ccusage), which this skill does not read: it reads GitHub-side queue and PR state. The request routes to /harness-ops:observability, invoked via the Skill tool, rather than being answered here."
---

/work-items:morning-brief

Add my local token burn rate and hook latency for this week to the morning brief.

The text below the command is the operator's request, not flags. No tracker, forge or shell is reachable in this session, so make no such call: say what this skill does with the request, and why.
