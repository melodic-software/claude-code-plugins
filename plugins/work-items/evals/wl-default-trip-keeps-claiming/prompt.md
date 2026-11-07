---
description: 'Legacy work-loop 23. A lane not opted in to pausing clears the legacy latch fields at cycle start, keeps claiming through a 96% seven-day reading at full model, effort and review depth, and reports the window and the operator''s three options. three-options reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, rate-limit]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The lane reads LOOP_LANE_RATE_LIMIT_PAUSE from its environment, finds it unset, clears rate_limit_latch, paused_until and latched_account together, sets no new latch, keeps claiming and dispatching the two items under its normal cap with no lower model, effort or review depth, and reports the seven-day window, its used_percentage and resets_at, and the options: continue, switch accounts, or opt in to pausing with LOOP_LANE_RATE_LIMIT_PAUSE=1.'
---

/work-items:work-loop

Cycle start. Durable state still carries rate_limit_latch=true, a future paused_until and a latched_account, left by a run under the former default-on pause. The snapshot file holds one snapshot captured 3 minutes ago whose seven-day window reads 96% with a resets_at three days out. Two admitted items are on the frontier. `printenv LOOP_LANE_RATE_LIMIT_PAUSE` prints nothing.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
