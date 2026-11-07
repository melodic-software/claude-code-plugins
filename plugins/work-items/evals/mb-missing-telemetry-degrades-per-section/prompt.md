---
description: "Legacy morning-brief 4. Reaches SKILL.md's telemetry-issue and queue-label paragraphs after 'What each section reports': with no telemetry issue and none of the queue labels, each section degrades on its own and the rest of the brief renders. names-empty-states reads the reply; meets-expectations judges the rest. Bash is listed only so SKILL.md's pre-computed context lines load; needs --allow-tools Bash. Graded on the reply."
tags: [work-items, morning-brief, routine, degraded-section]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "No. Each section degrades on its own: the Lane telemetry section reports \"no telemetry issue found\" and the Queues section reports \"no queue labels found\", while every other section still renders. Queue labels are filtered to the ones that actually exist in the target repo so a differently-labeled repo does not show misleading 0/? rows; --queue-labels and --telemetry-issue pin a custom set or a specific issue."
---

/work-items:morning-brief

I ran /work-items:morning-brief in a repo that has no loop-lane telemetry issue and none of the melodic-software queue labels. Should the brief fail?

The text below the command is the operator's question, not flags. No tracker, forge or shell is reachable in this session, so make no such call: answer from what this skill states.
