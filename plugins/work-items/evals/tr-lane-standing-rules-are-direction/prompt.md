---
description: 'Legacy triage 6. In an AFK lane whose standing rules authorize triage mutations, the rules are the direction the gate needs, so the run proceeds without a human turn; with ai_disclaimer true from the repository, every comment it creates opens with the AI disclaimer. disclaimer-text and no-question read the reply. Read-only tools, graded on the reply.'
tags: [triage, direction-gate, lane, ai-disclaimer]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run treats the lane''s standing rules as the direction, proceeds through verification and outcome without waiting, resolves ai_disclaimer true from the repository and starts every comment and item it creates with the disclaimer line, routing writes through the adapter and the seam.'
---

/work-items:triage 71

Running unattended as a /loop AFK lane whose standing rules authorize triage label and comment mutations; the repository's docs/conventions/work-items.yaml sets ai_disclaimer: true; #71 is an external bug report you have just reproduced.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
