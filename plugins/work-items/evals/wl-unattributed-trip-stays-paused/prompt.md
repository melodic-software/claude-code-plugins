---
description: 'Legacy work-loop 13. A 96% trip from a snapshot with no account.email is unattributed: latched_account stays null, the readable .claude.json is not a switch, and the lane stays paused until resets_at. latched-account-null reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, rate-limit, account-switch]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The pause entry is unattributed: latched_account stays null, the .claude.json account is not a switch, and the lane stays paused until the five-hour resets_at with rate_limit_latch set, finishing in-flight work and claiming nothing new. On its first later wake it records the .claude.json fingerprint as latched_account and continues the ordinary re-evaluation, never printing the address.'
---

/work-items:work-loop

Cycle start, and the lane is not paused. The snapshot file holds one snapshot captured 4 minutes ago whose five-hour window reads 96% and which has no account.email field. ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json names a readable .oauthAccount.emailAddress. Durable state carries no latched_account. The lane's session environment sets LOOP_LANE_RATE_LIMIT_PAUSE=1 (the operator opted in to pausing).

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
