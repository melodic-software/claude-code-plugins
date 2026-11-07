---
description: 'Legacy work-loop 12. A 96% trip from account A''s snapshot after the operator moved to account B: latched_account is A''s fingerprint, the switch is seen at pause entry, B''s windows are unknown, so the latch drops to reactive-only with an account-switch: unknown line. account-switch-unknown reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, rate-limit, account-switch]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The trip latches account A''s fingerprint with paused_until in one write, reads .claude.json, sees B differs and re-evaluates at once; no fresh snapshot attributes B, so it clears rate_limit_latch, paused_until and latched_account together, runs reactive-only, reports ''account-switch: unknown'' and does not sleep until A''s resets_at.'
---

/work-items:work-loop

Cycle start, and the lane is not paused. The snapshot file holds one snapshot captured 4 minutes ago whose account.email names account A and whose five-hour window reads 96%. After that snapshot the operator switched to account B: ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json now names account B, and no other snapshot exists. Durable state carries no latched_account. The lane's session environment sets LOOP_LANE_RATE_LIMIT_PAUSE=1 (the operator opted in to pausing).

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
