---
description: 'Legacy work-loop 14. A paused lane wakes on an account switch whose fresh snapshot has only a five-hour window at 40%: the one plausible window decides, so it resumes and clears the latch fields, with no reactive-only fallback. account-switch-resumed reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, rate-limit, account-switch]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The lane re-evaluates against the new account from one read of the fresh snapshot. The only plausible window is below 95, so it resumes, clears rate_limit_latch, paused_until and latched_account together, does not treat the absent seven-day window as blocking, does not fall to reactive-only, and adds ''account-switch: resumed'' to the report.'
---

/work-items:work-loop

The lane is paused after a 98% five-hour trip. Durable state carries rate_limit_latch=true, a future paused_until, and latched_account set to a 16-hex fingerprint. A wake fires: ${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json now names a different .oauthAccount.emailAddress than the latched fingerprint. The snapshot file holds one snapshot captured 2 minutes ago whose account.email matches the new account, with the five-hour window at 40% and no seven-day window. The lane's session environment sets LOOP_LANE_RATE_LIMIT_PAUSE=1 (the operator opted in to pausing).

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
