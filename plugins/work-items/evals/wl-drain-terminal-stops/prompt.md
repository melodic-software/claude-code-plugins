---
description: 'Legacy work-loop 3. A --drain cycle end where two retained ids have open non-draft closing PRs and one is human-gated with no PR in flight: the drain-terminal state, so the lane writes its final report and stops instead of scheduling a wakeup. stops-no-wakeup reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, drain, exit]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The exit test runs over the cycle-start snapshot''s retained ids through the adapter''s Open linked PRs operation. The full exit is not met, but every remaining open item is human-gated with no PR in flight, the drain-terminal state, so the lane writes its final report (escalated items first, then closed and PR''d), updates the state block and stops cleanly with no ScheduleWakeup.'
---

/work-items:work-loop --drain

Cycle end. The cycle-start snapshot retained three open ids: two have open non-draft PRs that GitHub links as closing them, one is human-gated awaiting an escalation answer. No PR is in flight for the human-gated item.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
